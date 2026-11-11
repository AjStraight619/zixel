//! `zixel new <name>`: scaffold a game project that depends on this checkout.
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const NewArgs = @import("NewArgs.zig");

/// Package name of the engine, as declared in its build.zig.zon and build.zig.
const engine_package = "zixel_new";

const build_zig_tmpl =
    \\const std = @import("std");
    \\
    \\pub fn build(b: *std.Build) void {{
    \\    const target = b.standardTargetOptions(.{{}});
    \\    const optimize = b.standardOptimizeOption(.{{}});
    \\
    \\    // The Zixel engine, declared in build.zig.zon.
    \\    const zixel_dep = b.dependency("{[engine]s}", .{{
    \\        .target = target,
    \\        .optimize = optimize,
    \\    }});
    \\
    \\    const exe = b.addExecutable(.{{
    \\        .name = "{[name]s}",
    \\        .root_module = b.createModule(.{{
    \\            .root_source_file = b.path("src/main.zig"),
    \\            .target = target,
    \\            .optimize = optimize,
    \\            .imports = &.{{
    \\                .{{ .name = "{[engine]s}", .module = zixel_dep.module("{[engine]s}") }},
    \\            }},
    \\        }}),
    \\    }});
    \\    b.installArtifact(exe);
    \\
    \\    const run_cmd = b.addRunArtifact(exe);
    \\    if (b.args) |args| run_cmd.addArgs(args);
    \\    const run_step = b.step("run", "Run the game");
    \\    run_step.dependOn(&run_cmd.step);
    \\}}
    \\
;

const zon_tmpl =
    \\.{{
    \\    .name = .{[package]s},
    \\    .version = "0.1.0",
    \\    .fingerprint = 0x{[fingerprint]x},
    \\    .minimum_zig_version = "{[zig_version]s}",
    \\    .dependencies = .{{
    \\        .{[engine]s} = .{{
    \\            .path = "{[engine_path]s}",
    \\        }},
    \\    }},
    \\    .paths = .{{
    \\        "build.zig",
    \\        "build.zig.zon",
    \\        "src",
    \\        "assets",
    \\        "settings",
    \\    }},
    \\}}
    \\
;

const main_zig_tmpl =
    \\const std = @import("std");
    \\const zixel = @import("{[engine]s}");
    \\
    \\pub fn main() !void {{
    \\    // Initialize the engine with default settings
    \\    var engine = try zixel.Engine.init(std.heap.smp_allocator, .{{
    \\        .window = .{{
    \\            .title = "{[name]s}",
    \\            .width = 1280,
    \\            .height = 720,
    \\        }},
    \\    }});
    \\
    \\    // Run the game loop; the engine cleans up when the window closes.
    \\    engine.run();
    \\}}
    \\
;

const project_json_tmpl =
    \\{{
    \\    "name": "{[name]s}",
    \\    "version": "0.1.0",
    \\    "start_scene": "assets/scenes/main.json"
    \\}}
    \\
;

const main_scene_json =
    \\{
    \\    "entities": [],
    \\    "meta": { "created_at": "now" }
    \\}
    \\
;

const gitignore = ".zig-cache/\nzig-out/\n";

pub const Error = error{
    InvalidProjectName,
    UnsupportedOption,
    DirectoryNotEmpty,
};

/// The project name is written into Zig, ZON and JSON string literals and used
/// as an executable name, so keep it to characters that need no escaping.
fn isValidProjectName(name: []const u8) bool {
    if (name.len == 0 or name.len > 64) return false;
    if (name[0] == '.' or name[0] == '-') return false;
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-' and c != '.') return false;
    }
    return true;
}

/// Zig package names are bare identifiers of at most 32 bytes.
fn packageName(buffer: *[32]u8, project_name: []const u8) []const u8 {
    var len: usize = 0;
    if (std.ascii.isDigit(project_name[0])) {
        buffer[0] = '_';
        len = 1;
    }
    for (project_name) |c| {
        if (len == buffer.len) break;
        buffer[len] = if (std.ascii.isAlphanumeric(c)) c else '_';
        len += 1;
    }
    return buffer[0..len];
}

/// Mirrors the compiler's package fingerprint: a random non-reserved id in the
/// low 32 bits and the CRC32 of the package name in the high 32 bits.
fn fingerprint(io: std.Io, package: []const u8) u64 {
    var id: u32 = 0;
    while (id == 0 or id == std.math.maxInt(u32)) {
        var bytes: [4]u8 = undefined;
        io.random(&bytes);
        id = std.mem.readInt(u32, &bytes, .little);
        // No entropy source: fall back to something that is at least valid.
        if (id == 0) id = std.hash.Crc32.hash(package) | 1;
    }
    return (@as(u64, std.hash.Crc32.hash(package)) << 32) | id;
}

/// Creates the project `args.name` (a directory path) inside `base`.
/// `engine_dir` is the absolute path of the Zixel checkout to depend on.
/// Explains any refusal on `out` before returning the error.
pub fn run(
    alloc: Allocator,
    io: std.Io,
    out: *std.Io.Writer,
    base: std.Io.Dir,
    args: NewArgs,
    engine_dir: []const u8,
) !void {
    const name = std.fs.path.basename(args.name);
    if (!isValidProjectName(name)) {
        try out.print(
            "error: '{s}' is not a usable project name (letters, digits, '_', '-' and '.'; must not start with '.' or '-')\n",
            .{name},
        );
        return Error.InvalidProjectName;
    }
    if (args.sample) |sample| {
        try out.print("error: --sample {s}: starting from a sample is not supported yet\n", .{sample});
        return Error.UnsupportedOption;
    }

    // Never write into a directory that already has content.
    if (base.openDir(io, args.name, .{ .iterate = true })) |existing| {
        defer existing.close(io);
        var it = existing.iterate();
        if (try it.next(io) != null) {
            try out.print("error: directory '{s}' already exists and is not empty\n", .{args.name});
            return Error.DirectoryNotEmpty;
        }
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    try base.createDirPath(io, args.name);
    var dir = try base.openDir(io, args.name, .{});
    defer dir.close(io);

    // Dependency paths in build.zig.zon are relative to the project.
    const project_path = try base.realPathFileAlloc(io, args.name, alloc);
    defer alloc.free(project_path);
    const relative_engine = try std.fs.path.relative(alloc, project_path, null, project_path, engine_dir);
    defer alloc.free(relative_engine);
    std.mem.replaceScalar(u8, relative_engine, '\\', '/');

    var package_buffer: [32]u8 = undefined;
    const package = packageName(&package_buffer, name);

    try out.print("Creating Zixel project '{s}' in {s}\n", .{ name, project_path });

    for ([_][]const u8{ "src", "assets/scenes", "assets/sprites", "settings" }) |sub_path| {
        try dir.createDirPath(io, sub_path);
    }

    try writeTemplate(alloc, io, dir, "build.zig", build_zig_tmpl, .{ .name = name, .engine = engine_package });
    try writeTemplate(alloc, io, dir, "build.zig.zon", zon_tmpl, .{
        .package = package,
        .fingerprint = fingerprint(io, package),
        .zig_version = builtin.zig_version_string,
        .engine = engine_package,
        .engine_path = relative_engine,
    });
    try writeTemplate(alloc, io, dir, "src/main.zig", main_zig_tmpl, .{ .name = name, .engine = engine_package });
    try writeTemplate(alloc, io, dir, "settings/project.json", project_json_tmpl, .{ .name = name });
    try dir.writeFile(io, .{ .sub_path = "assets/scenes/main.json", .data = main_scene_json });
    try dir.writeFile(io, .{ .sub_path = ".gitignore", .data = gitignore });

    // The engine location was recorded when this CLI was built; say so if the
    // checkout has moved, rather than leaving a confusing build error for later.
    const engine_zon = try std.fs.path.join(alloc, &.{ engine_dir, "build.zig.zon" });
    defer alloc.free(engine_zon);
    std.Io.Dir.cwd().access(io, engine_zon, .{}) catch {
        try out.print(
            "warning: Zixel was not found at {s}; update the dependency path in build.zig.zon\n",
            .{engine_dir},
        );
    };

    try out.print("Done. Next: cd {s} && zig build run\n", .{args.name});
}

fn writeTemplate(
    alloc: Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    sub_path: []const u8,
    comptime template: []const u8,
    values: anytype,
) !void {
    const content = try std.fmt.allocPrint(alloc, template, values);
    defer alloc.free(content);
    try dir.writeFile(io, .{ .sub_path = sub_path, .data = content });
}

test "new creates a complete project and refuses to overwrite it" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var discard: std.Io.Writer.Discarding = .init(&.{});
    const out = &discard.writer;

    const engine_dir = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(engine_dir);

    try run(alloc, io, out, tmp.dir, .{ .name = "games/my-game" }, engine_dir);

    for ([_][]const u8{
        "games/my-game/build.zig",
        "games/my-game/build.zig.zon",
        "games/my-game/src/main.zig",
        "games/my-game/settings/project.json",
        "games/my-game/assets/scenes/main.json",
        "games/my-game/assets/sprites",
        "games/my-game/.gitignore",
    }) |path| try tmp.dir.access(io, path, .{});

    const zon = try tmp.dir.readFileAlloc(io, "games/my-game/build.zig.zon", alloc, .limited(4096));
    defer alloc.free(zon);
    // A bare identifier for the package, and a path back up to the engine.
    try std.testing.expect(std.mem.indexOf(u8, zon, ".name = .my_game,") != null);
    try std.testing.expect(std.mem.indexOf(u8, zon, ".path = \"../..\"") != null);

    const project = try tmp.dir.readFileAlloc(io, "games/my-game/settings/project.json", alloc, .limited(4096));
    defer alloc.free(project);
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, project, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("my-game", parsed.value.object.get("name").?.string);

    // A second run must not touch the existing project.
    try tmp.dir.writeFile(io, .{ .sub_path = "games/my-game/src/main.zig", .data = "edited" });
    try std.testing.expectError(Error.DirectoryNotEmpty, run(alloc, io, out, tmp.dir, .{ .name = "games/my-game" }, engine_dir));
    const main_source = try tmp.dir.readFileAlloc(io, "games/my-game/src/main.zig", alloc, .limited(4096));
    defer alloc.free(main_source);
    try std.testing.expectEqualStrings("edited", main_source);
}

test "new rejects unusable names and unsupported options without creating anything" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var discard: std.Io.Writer.Discarding = .init(&.{});
    const out = &discard.writer;

    for ([_][]const u8{ "--help", ".hidden", "has space", "quote\"d", "" }) |name| {
        try std.testing.expectError(Error.InvalidProjectName, run(alloc, io, out, tmp.dir, .{ .name = name }, "/nowhere"));
    }
    try std.testing.expectError(Error.UnsupportedOption, run(alloc, io, out, tmp.dir, .{ .name = "game", .sample = "physics" }, "/nowhere"));

    var it = tmp.dir.iterate();
    try std.testing.expect(try it.next(io) == null);
}

test "fingerprints carry the package name checksum and a valid id" {
    const value = fingerprint(std.testing.io, "zixel_new");
    try std.testing.expectEqual(@as(u64, 0x9090fe3f), value >> 32);
    const id: u32 = @truncate(value);
    try std.testing.expect(id != 0 and id != std.math.maxInt(u32));

    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings("_3d_game", packageName(&buffer, "3d-game"));
    try std.testing.expectEqual(@as(usize, 32), packageName(&buffer, "a" ** 64).len);
}
