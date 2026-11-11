const std = @import("std");

pub fn scaffold(alloc: std.mem.Allocator, io: std.Io, root_path: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, root_path);

    const folders = [_][]const u8{
        "assets",
        "assets/scenes",
        "assets/sprites",
        "settings",
    };

    for (folders) |f| {
        const full_path = try std.fs.path.join(alloc, &.{ root_path, f });
        defer alloc.free(full_path);
        try cwd.createDirPath(io, full_path);
    }

    const default_config =
        \\{
        \\    "name": "New Project",
        \\    "version": "0.1.0",
        \\    "start_scene": "assets/scenes/main.json"
        \\}
    ;

    const default_scene =
        \\{
        \\    "entities": [],
        \\    "meta": { "created_at": "now" }
        \\}
    ;

    const project_json_path = try std.fs.path.join(alloc, &.{ root_path, "settings/project.json" });
    defer alloc.free(project_json_path);
    try writeIfMissing(io, cwd, project_json_path, default_config);

    const main_scene_path = try std.fs.path.join(alloc, &.{ root_path, "assets/scenes/main.json" });
    defer alloc.free(main_scene_path);
    try writeIfMissing(io, cwd, main_scene_path, default_scene);
}

/// Creates the file with default content, leaving an existing file untouched:
/// opening a project must never reset what the user already has.
fn writeIfMissing(io: std.Io, dir: std.Io.Dir, sub_path: []const u8, data: []const u8) !void {
    const file = dir.createFile(io, sub_path, .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return err,
    };
    defer file.close(io);
    try file.writeStreamingAll(io, data);
}

test "scaffold creates a new project and preserves an existing one" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(root);
    const project_path = try std.fs.path.join(alloc, &.{ root, "game" });
    defer alloc.free(project_path);

    try scaffold(alloc, io, project_path);
    const created = try tmp.dir.readFileAlloc(io, "game/settings/project.json", alloc, .limited(4096));
    defer alloc.free(created);
    try std.testing.expect(std.mem.indexOf(u8, created, "\"New Project\"") != null);
    try tmp.dir.access(io, "game/assets/sprites", .{});

    try tmp.dir.writeFile(io, .{ .sub_path = "game/settings/project.json", .data = "my settings" });
    try tmp.dir.writeFile(io, .{ .sub_path = "game/assets/scenes/main.json", .data = "my scene" });
    try scaffold(alloc, io, project_path);
    for ([_][2][]const u8{
        .{ "game/settings/project.json", "my settings" },
        .{ "game/assets/scenes/main.json", "my scene" },
    }) |entry| {
        const content = try tmp.dir.readFileAlloc(io, entry[0], alloc, .limited(4096));
        defer alloc.free(content);
        try std.testing.expectEqualStrings(entry[1], content);
    }
}
