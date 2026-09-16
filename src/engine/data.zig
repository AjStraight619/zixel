const std = @import("std");
const Allocator = std.mem.Allocator;
const BodyKind = @import("../physics/Body.zig").BodyKind;
const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
const Vec2 = @import("../math/Vec2.zig");
const EntityDef = @import("Entity.zig").EntityDef;

pub fn save(alloc: Allocator, io: std.Io, path: []const u8, scene_name: []const u8, defs: []const EntityDef) !void {
    const filename = try std.fmt.allocPrint(alloc, "{s}.json", .{scene_name});
    defer alloc.free(filename);

    const full_path = try std.fs.path.join(alloc, &[_][]const u8{ path, "assets", "scenes", filename });
    defer alloc.free(full_path);

    if (std.fs.path.dirname(full_path)) |dir| {
        try std.Io.Dir.cwd().createDirPath(io, dir);
    }

    var out: std.Io.Writer.Allocating = .init(alloc);
    const writer = &out.writer;
    defer out.deinit();

    const scene_data = .{
        .version = "1.0",
        .name = scene_name,
        .entities = defs,
    };

    try std.json.Stringify.value(scene_data, .{}, writer);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = full_path, .data = out.written() });
}

test "save scene" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup(); // This deletes the folder when the test finishes!

    const tmp_root_path = try temp_dir.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(tmp_root_path);

    const defs = &[_]EntityDef{
        makeDef("Player", 100, 200, .dynamic),
        makeDef("Ground", 0, 500, .static),
    };

    try save(alloc, io, tmp_root_path, "TestScene", defs);

    const json_content = try temp_dir.dir.readFileAlloc(io, "assets/scenes/TestScene.json", alloc, .limited(4096));
    defer alloc.free(json_content);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, json_content, .{});
    defer parsed.deinit();
    const scene = parsed.value.object;
    try std.testing.expectEqualStrings("1.0", scene.get("version").?.string);
    try std.testing.expectEqualStrings("TestScene", scene.get("name").?.string);
    const entities = scene.get("entities").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), entities.len);
    try std.testing.expectEqualStrings("Player", entities[0].object.get("name").?.string);
    try std.testing.expectEqualStrings("Ground", entities[1].object.get("name").?.string);
}

/// Quick helper to make definitions without all the boilerplate
fn makeDef(name: []const u8, x: f32, y: f32, kind: BodyKind) EntityDef {
    return EntityDef{
        .name = name,
        .position = .{ .x = x, .y = y },
        .rotation = 0,
        .tags = &.{},
        .owner = .none,

        // Setup a standard test body (10x10 box)
        .body = .{
            .kind = kind,
            .shape = PhysicsShape.rect(10, 10),
            .mass = if (kind == .dynamic) 1.0 else 0.0,
            .velocity = Vec2.zero,
        },

        // Setup a standard visual
        .sprite = .{
            .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 }, // Red
            .texture_path = null,
        },
    };
}
