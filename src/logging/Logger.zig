//! Optional application-owned sink for std.log: stderr, a file, and recent records.
//! No UI dependencies. Configuration is immutable while producers are running.
const std = @import("std");
const Logger = @This();

pub const Config = struct {
    stderr: bool = true,
    /// Append to this file. Its parent directory must already exist.
    /// One process owns a file at a time; use separate files for editor and game.
    file_path: ?[]const u8 = null,
    capacity: usize = 256,
    level: std.log.Level = .info,
    /// Borrowed for the logger's lifetime. Like Zig's --debug-log <scope>.
    debug_scopes: []const []const u8 = &.{},
};

pub const Record = struct {
    level: std.log.Level,
    // Scope names come from comptime enum literals and have static lifetime.
    scope: []const u8,
    bytes: [4096]u8 = undefined,
    len: usize = 0,

    pub fn text(self: *const Record) []const u8 {
        return self.bytes[0..self.len];
    }
};

alloc: std.mem.Allocator,
io: std.Io,
cfg: Config,
mutex: std.Io.Mutex = .init,
records: []Record,
start: usize = 0,
count: usize = 0,
/// Bumped whenever the history changes, so readers can skip unchanged snapshots.
revision: u64 = 0,
file: ?std.Io.File = null,
file_offset: u64 = 0,

threadlocal var emitting: bool = false;

pub fn init(alloc: std.mem.Allocator, io: std.Io, cfg: Config) !Logger {
    const records = try alloc.alloc(Record, cfg.capacity);
    errdefer alloc.free(records);
    var result = Logger{ .alloc = alloc, .io = io, .cfg = cfg, .records = records };
    if (cfg.file_path) |path| {
        const file = try std.Io.Dir.cwd().createFile(io, path, .{
            .truncate = false,
            .lock = .exclusive,
            .lock_nonblocking = true,
        });
        errdefer file.close(io);
        result.file_offset = (try file.stat(io)).size;
        result.file = file;
    }
    return result;
}

/// Stop all producers and detach the application's logFn before deinitializing.
pub fn deinit(self: *Logger) void {
    if (self.file) |file| file.close(self.io);
    self.alloc.free(self.records);
    self.* = undefined;
}

pub fn enabled(self: *const Logger, level: std.log.Level, scope: []const u8) bool {
    if (@intFromEnum(level) <= @intFromEnum(self.cfg.level)) return true;
    for (self.cfg.debug_scopes) |selected| {
        if (std.mem.eql(u8, scope, selected)) return true;
    }
    return false;
}

pub fn log(self: *Logger, comptime level: std.log.Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype) void {
    if (!self.enabled(level, @tagName(scope)) or emitting) return;
    emitting = true;
    defer emitting = false;

    // Format outside the lock: user formatters can themselves attempt logging.
    var record = makeRecord(self.io, level, @tagName(scope), format, args);
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    self.writeLocked(&record);
}

/// Best effort for Zig panics. Never wait on a possibly interrupted log call.
/// Signal handlers must not call this; it is not async-signal-safe.
pub fn recordPanic(self: *Logger, message: []const u8) void {
    if (emitting or !self.mutex.tryLock()) return;
    defer self.mutex.unlock(self.io);
    emitting = true;
    defer emitting = false;
    var record = makeRecord(self.io, .err, "zixel_panic", "{s}", .{message});
    self.writeLocked(&record);
}

/// Copy newest records in chronological order; the UI never holds the log lock.
pub fn snapshot(self: *Logger, out: []Record) []Record {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    const count = @min(out.len, self.count);
    for (out[0..count], 0..) |*record, i| {
        record.* = self.records[(self.start + self.count - count + i) % self.records.len];
    }
    return out[0..count];
}

/// Like `snapshot`, but copies only when the history changed since the call
/// that last set `seen`. Returns null, leaving `out` untouched, when it did not.
/// Start with `seen.* = 0`: an untouched logger has nothing to copy.
pub fn snapshotIfChanged(self: *Logger, seen: *u64, out: []Record) ?[]Record {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    if (seen.* == self.revision) return null;
    seen.* = self.revision;
    const count = @min(out.len, self.count);
    for (out[0..count], 0..) |*record, i| {
        record.* = self.records[(self.start + self.count - count + i) % self.records.len];
    }
    return out[0..count];
}

/// Clear console history only. The file keeps its diagnostic history.
pub fn clear(self: *Logger) void {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    self.start = 0;
    self.count = 0;
    self.revision += 1;
}

fn remember(self: *Logger, record: *const Record) void {
    self.revision += 1;
    if (self.records.len == 0) return;
    self.records[(self.start + self.count) % self.records.len] = record.*;
    if (self.count == self.records.len) {
        self.start = (self.start + 1) % self.records.len;
    } else self.count += 1;
}

fn writeLocked(self: *Logger, record: *const Record) void {
    self.remember(record);
    if (self.cfg.stderr) std.Io.File.stderr().writeStreamingAll(self.io, record.text()) catch {};
    if (self.file) |file| {
        // No userspace buffering: records reach the OS before this call returns.
        // This is not an fsync/power-loss durability guarantee.
        file.writePositionalAll(self.io, record.text(), self.file_offset) catch |err| {
            file.close(self.io);
            self.file = null;
            const warning = makeRecord(self.io, .err, "zixel_logging", "File logging disabled after write failure: {s}", .{@errorName(err)});
            self.remember(&warning);
            std.Io.File.stderr().writeStreamingAll(self.io, warning.text()) catch {};
            return;
        };
        self.file_offset += record.len;
    }
}

fn makeRecord(io: std.Io, comptime level: std.log.Level, comptime scope: []const u8, comptime format: []const u8, args: anytype) Record {
    var record = Record{ .level = level, .scope = scope };
    var writer = std.Io.Writer.fixed(&record.bytes);
    const ms = std.Io.Clock.real.now(io).toMilliseconds();
    // Clamp an invalid system clock to the range supported by the date formatter.
    const stamp: u64 = @intCast(std.math.clamp(ms, 0, 253402300799999));
    const epoch = std.time.epoch.EpochSeconds{ .secs = stamp / 1000 };
    const year = epoch.getEpochDay().calculateYearDay();
    const date = year.calculateMonthDay();
    const time = epoch.getDaySeconds();
    writer.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z {s}({s}): ", .{
        year.year,              date.month.numeric(),      @as(u16, date.day_index) + 1,
        time.getHoursIntoDay(), time.getMinutesIntoHour(), time.getSecondsIntoMinute(),
        stamp % 1000,           level.asText(),            scope,
    }) catch {};
    var message_buffer: [2048]u8 = undefined;
    var message = std.Io.Writer.fixed(&message_buffer);
    var truncated = false;
    message.print(format, args) catch {
        truncated = true;
    };
    // Keep each event on one line, including messages from third-party callbacks.
    for (message.buffered()) |byte| {
        if (writer.end + 16 >= record.bytes.len) {
            truncated = true;
            break;
        }
        switch (byte) {
            '\n' => writer.writeAll("\\n") catch {},
            '\r' => writer.writeAll("\\r") catch {},
            0...9, 11...12, 14...31, 127 => writer.writeByte('?') catch {},
            else => writer.writeByte(byte) catch {},
        }
    }
    if (truncated) writer.writeAll(" [truncated]") catch {};
    writer.writeByte('\n') catch {};
    record.len = writer.end;
    return record;
}

test "scope filtering and bounded history preserve newest records" {
    var logger = try Logger.init(std.testing.allocator, std.testing.io, .{
        .stderr = false,
        .capacity = 2,
        .debug_scopes = &.{"physics"},
    });
    defer logger.deinit();
    logger.log(.info, .editor, "first", .{});
    logger.log(.debug, .nav, "hidden", .{});
    logger.log(.debug, .physics, "contacts={d}", .{4});
    logger.log(.warn, .editor, "last", .{});
    var records: [3]Record = undefined;
    const snapshot_records = logger.snapshot(&records);
    try std.testing.expectEqual(@as(usize, 2), snapshot_records.len);
    try std.testing.expectEqualStrings("physics", snapshot_records[0].scope);
    try std.testing.expect(std.mem.endsWith(u8, snapshot_records[0].text(), "debug(physics): contacts=4\n"));
    try std.testing.expectEqualStrings("editor", snapshot_records[1].scope);
    logger.clear();
    try std.testing.expectEqual(@as(usize, 0), logger.snapshot(&records).len);
    // Snapshots own their text; clearing/overwriting the logger cannot invalidate them.
    try std.testing.expect(std.mem.endsWith(u8, records[1].text(), "warning(editor): last\n"));
}

test "snapshotIfChanged copies only after the history changes" {
    var logger = try Logger.init(std.testing.allocator, std.testing.io, .{ .stderr = false, .capacity = 4 });
    defer logger.deinit();
    var records: [4]Record = undefined;
    var seen: u64 = 0;
    try std.testing.expect(logger.snapshotIfChanged(&seen, &records) == null);
    logger.log(.info, .editor, "one", .{});
    try std.testing.expectEqual(@as(usize, 1), logger.snapshotIfChanged(&seen, &records).?.len);
    try std.testing.expect(logger.snapshotIfChanged(&seen, &records) == null);
    logger.log(.debug, .editor, "filtered out", .{});
    try std.testing.expect(logger.snapshotIfChanged(&seen, &records) == null);
    logger.clear();
    try std.testing.expectEqual(@as(usize, 0), logger.snapshotIfChanged(&seen, &records).?.len);
}

test "messages are bounded and control characters cannot forge records" {
    var logger = try Logger.init(std.testing.allocator, std.testing.io, .{ .stderr = false, .capacity = 2 });
    defer logger.deinit();
    logger.log(.info, .test_scope, "one\ntwo\r\x00\x1b", .{});
    logger.log(.info, .test_scope, "{s}", .{&([_]u8{'x'} ** 5000)});
    var records: [2]Record = undefined;
    _ = logger.snapshot(&records);
    try std.testing.expect(std.mem.endsWith(u8, records[0].text(), "one\\ntwo\\r??\n"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, records[0].text(), "\n"));
    try std.testing.expect(std.mem.endsWith(u8, records[1].text(), " [truncated]\n"));
    try std.testing.expect(records[1].len <= records[1].bytes.len);
}

test "file output is immediately readable, appends across sessions and survives console clear" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "session.log", .data = "previous session\n" });
    const path = try tmp.dir.realPathFileAlloc(io, "session.log", alloc);
    defer alloc.free(path);
    {
        var logger = try Logger.init(alloc, io, .{ .stderr = false, .file_path = path, .capacity = 0 });
        defer logger.deinit();
        logger.log(.info, .editor, "loaded scene", .{});
        logger.clear();
        logger.recordPanic("example panic");
        const content = try tmp.dir.readFileAlloc(io, "session.log", alloc, .limited(8192));
        defer alloc.free(content);
        try std.testing.expect(std.mem.startsWith(u8, content, "previous session\n"));
        try std.testing.expect(std.mem.indexOf(u8, content, "info(editor): loaded scene\n") != null);
        try std.testing.expect(std.mem.endsWith(u8, content, "error(zixel_panic): example panic\n"));
    }
    var logger = try Logger.init(alloc, io, .{ .stderr = false, .file_path = path });
    defer logger.deinit();
    logger.log(.info, .editor, "next session", .{});
    const content = try tmp.dir.readFileAlloc(io, "session.log", alloc, .limited(8192));
    defer alloc.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "example panic") != null);
    try std.testing.expect(std.mem.endsWith(u8, content, "info(editor): next session\n"));
}

test "concurrent producers preserve complete records" {
    var logger = try Logger.init(std.testing.allocator, std.testing.io, .{ .stderr = false, .capacity = 128 });
    defer logger.deinit();
    const Worker = struct {
        fn run(sink: *Logger, id: usize) void {
            for (0..32) |i| sink.log(.info, .worker, "worker={d} item={d}", .{ id, i });
        }
    };
    var threads: [4]std.Thread = undefined;
    var started: usize = 0;
    {
        defer for (threads[0..started]) |thread| thread.join();
        for (&threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, Worker.run, .{ &logger, i });
            started += 1;
        }
    }
    const records = try std.testing.allocator.alloc(Record, 128);
    defer std.testing.allocator.free(records);
    try std.testing.expectEqual(@as(usize, 128), logger.snapshot(records).len);
    for (0..4) |id| {
        for (0..32) |i| {
            var buffer: [64]u8 = undefined;
            const suffix = try std.fmt.bufPrint(&buffer, "worker={d} item={d}\n", .{ id, i });
            var found: usize = 0;
            for (records) |*record| {
                if (std.mem.endsWith(u8, record.text(), suffix)) found += 1;
            }
            try std.testing.expectEqual(@as(usize, 1), found);
        }
    }
}

test "panic recording does not deadlock when logging is already locked" {
    var logger = try Logger.init(std.testing.allocator, std.testing.io, .{ .stderr = false });
    defer logger.deinit();
    logger.mutex.lockUncancelable(logger.io);
    logger.recordPanic("interrupted logger");
    logger.mutex.unlock(logger.io);
    var records: [1]Record = undefined;
    try std.testing.expectEqual(@as(usize, 0), logger.snapshot(&records).len);
}

test "file-open failure frees history storage" {
    try std.testing.expectError(error.FileNotFound, Logger.init(std.testing.allocator, std.testing.io, .{
        .stderr = false,
        .file_path = "directory-that-does-not-exist-zixel/session.log",
    }));
}

test "logging requires no further allocator calls after initialization" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var logger = try Logger.init(failing.allocator(), std.testing.io, .{ .stderr = false, .capacity = 2 });
    defer logger.deinit();
    for (0..100) |i| logger.log(.info, .scene, "entity={d}", .{i});
    logger.recordPanic("allocator exhausted");
    var records: [2]Record = undefined;
    try std.testing.expectEqual(@as(usize, 2), logger.snapshot(&records).len);
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 1), failing.allocations);
}

test "recursive custom formatters cannot recurse into the logger" {
    var logger = try Logger.init(std.testing.allocator, std.testing.io, .{ .stderr = false });
    defer logger.deinit();
    const Value = struct {
        logger: *Logger,
        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            self.logger.log(.info, .recursive, "nested", .{});
            try writer.writeAll("formatted");
        }
    };
    logger.log(.info, .outer, "{f}", .{Value{ .logger = &logger }});
    var records: [2]Record = undefined;
    try std.testing.expectEqual(@as(usize, 1), logger.snapshot(&records).len);
    try std.testing.expect(std.mem.endsWith(u8, records[0].text(), "info(outer): formatted\n"));
}
