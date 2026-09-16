const std = @import("std");
const Allocator = std.mem.Allocator;
const BodyKind = @import("../physics/body.zig").BodyKind;
const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
const Vec2 = @import("../math/vec2.zig");
const EntityDef = @import("Entity.zig").EntityDef;

pub fn save(alloc: Allocator, path: []const u8, scene_name: []const u8, defs: []const EntityDef) !void {
    const filename = try std.fmt.allocPrint(alloc, "{s}.json", .{scene_name});
    defer alloc.free(filename);

    const full_path = try std.fs.path.join(alloc, &[_][]const u8{ path, "assets", "scenes", filename });
    defer alloc.free(full_path);

    if (std.fs.path.dirname(full_path)) |dir| {
        try std.fs.cwd().makePath(dir);
    }

    var out: std.io.Writer.Allocating = .init(alloc);
    const writer = &out.writer;
    defer out.deinit();

    const scene_data = .{
        .version = "1.0",
        .name = scene_name,
        .entities = defs,
    };

    try std.json.Stringify.value(scene_data, .{}, writer);

    const file = try std.fs.cwd().createFile(full_path, .{});
    defer file.close();

    try file.writeAll(out.written());

    // var ws = std.json.Stringify{ .writer = &buffer.writer, .options = .{ .whitespace = .indent_2 } };
    //
    // try ws.beginObject();
    //
    // try ws.objectField("version");
    // try ws.write("1.0");
    //
    // try ws.objectField("name");
    // try ws.write(scene_name);
    //
    // try ws.objectField("entities");
    // try ws.beginArray();
    //
    // for (defs) |def| {
    //     try writeEntity(&ws, def);
    // }
    //
    // try ws.endArray();
    // try ws.endObject();
    //
    // // Write json to file
    // const file = try std.fs.cwd().createFile(full_path, .{});
    // defer file.close();
    //
    // try file.writeAll(buffer.written());
}

// pub fn load(alloc: Allocator, path: []const u8) ![]EntityDef {
//     const file = try std.fs.cwd().openFile(path, .{});
//     defer file.close();
//
//     const file_size = (try file.stat()).size;
//     const buffer = try alloc.alloc(u8, file_size);
//     defer alloc.free(buffer);
//
//     _ = try file.readAll(buffer);
//
//     var parsed = try std.json.parseFromSlice(std.json.Value, alloc, buffer, .{});
//     defer parsed.deinit();
//
//     const root: std.json.Value = parsed.value;
//
//     const entities = root.object.get("entities").?.array;
//
//     const entity_list: std.ArrayList(EntityDef) = .empty;
//
//     errdefer {
//         for (entity_list.items) |*def| {
//             def.deinit(alloc);
//             entity_list.deinit(alloc);
//         }
//     }
//
//     for (entities.items) |entity| {
//         const def = try parseEntity(entity);
//         try entity_list.append(alloc, def);
//     }
//
//     return entity_list.toOwnedSlice(alloc);
// }

// fn parseEntity(alloc: Allocator, json_entity: std.json.Value) !EntityDef {}

fn writeEntity(ws: *std.json.Stringify, def: EntityDef) !void {
    try ws.beginObject();

    if (def.name) |n| {
        try ws.objectField("name");
        try ws.write(n);
    }

    try ws.objectField("position");
    try ws.beginObject();

    try ws.objectField("x");
    try ws.write(def.position.x);

    try ws.objectField("y");
    try ws.write(def.position.y);
    try ws.endObject();

    try ws.objectField("rotation");
    try ws.write(def.rotation);

    try ws.objectField("body");
    try ws.beginObject();
    try ws.objectField("kind");
    try ws.write(def.body.kind);
    try ws.objectField("mass");
    try ws.write(def.body.mass);

    try ws.objectField("shape");
    try ws.write(def.body.shape);
    try ws.endObject();

    try ws.objectField("sprite");
    try ws.beginObject();
    try ws.objectField("color");
    try ws.write(def.sprite.color);
    if (def.sprite.texture) |t| {
        try ws.objectField("texture");
        try ws.write(t);
    }
    try ws.endObject();

    try ws.objectField("tags");
    try ws.write(def.tags.items);

    try ws.endObject();
}

// fn save2(alloc: Allocator, path: []const u8, scene_name: []const u8, defs: []EntityDef) !void {
//     const filename = try std.fmt.allocPrint(alloc, "{s}.json", .{scene_name});
//     defer alloc.free(filename);
//
//     const full_path = try std.fs.path.join(alloc, .{ path, "assets", "scenes", filename });
//     defer alloc.free(full_path);
//
//     if (std.fs.path.dirname(full_path)) |dir| {
//         try std.fs.cwd().makePath(dir);
//     }
//
//     const file = try std.fs.cwd().createFile(full_path, .{});
//     defer file.close();
//
//     var writer_buf: [1024]u8 = undefined;
//     var writer = file.writer(&writer_buf);
//
//     // try writer.interface.writeAll(bytes: []const u8)
// }

test "save scene" {
    const alloc = std.testing.allocator;
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup(); // This deletes the folder when the test finishes!

    const tmp_root_path = try temp_dir.dir.realpathAlloc(alloc, ".");
    defer alloc.free(tmp_root_path);

    const defs = &[_]EntityDef{
        makeDef("Player", 100, 200, .dynamic),
        makeDef("Ground", 0, 500, .static),
    };

    try save(alloc, tmp_root_path, "TestScene", defs);

    const file = try temp_dir.dir.openFile("assets/scenes/TestScene.json", .{});
    defer file.close();

    const json_content = try file.readToEndAlloc(alloc, 4096);
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
