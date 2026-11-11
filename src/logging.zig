//! Modules use std.log.scoped; executables choose their own std_options.logFn.
pub const Logger = @import("logging/Logger.zig");
const std = @import("std");
const log = std.log.scoped(.zixel_sokol);

/// Sokol's callback may run on multiple threads and all strings are optional.
/// Preserve its subsystem tag, item ID, and source location even in release builds.
pub fn sokolLog(tag: [*c]const u8, level: u32, item: u32, message: [*c]const u8, line: u32, filename: [*c]const u8, _: ?*anyopaque) callconv(.c) void {
    const format = "{s}: {s} (item={d}, {s}:{d})";
    const args = .{ cString(tag), cString(message), item, cString(filename), line };
    switch (level) {
        0 => {
            log.err(format, args);
            // Sokol requires that a panic-level callback never returns.
            std.debug.panic(format, args);
        },
        1 => log.err(format, args),
        2 => log.warn(format, args),
        else => log.info(format, args),
    }
}

fn cString(ptr: [*c]const u8) []const u8 {
    return if (ptr == null) "unknown" else std.mem.span(ptr);
}

test {
    _ = Logger;
}
