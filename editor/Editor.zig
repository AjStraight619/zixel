const std = @import("std");
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;
const EntityDef = zixel.EntityDef;
const EntityHandle = zixel.EntityHandle;
const log = std.log.scoped(.zixel_editor);

const NewSceneDialog = @import("toolbar/file/NewSceneDialog.zig");

const Editor = @This();

alloc: Allocator,

world: ?*zixel.World = null,

// 1. Editor owns the dialog state
new_scene_dialog: NewSceneDialog,

/// A generational handle, so a selection never silently moves to another
/// entity that later reuses the same slot.
selected_entity: ?EntityHandle = null,

game_root_dir: []const u8,

show_scene_view: bool = true,
show_hierarchy: bool = true,
show_inspector: bool = true,
show_console: bool = true,
show_demo: bool = false,

entity_defs: std.ArrayList(EntityDef),
/// World entity spawned for each definition, index-aligned with `entity_defs`.
/// `EntityHandle.invalid` when there was no world to spawn into.
entity_handles: std.ArrayList(EntityHandle),
dirty: bool = false,
scene_file_path: ?[]const u8 = null,

pub fn init(alloc: Allocator, root_path: []const u8) !Editor {
    const root_copy = try alloc.dupe(u8, root_path);

    return .{
        .alloc = alloc,
        .entity_defs = .empty,
        .entity_handles = .empty,
        .game_root_dir = root_copy,
        // 2. Initialize dialog
        .new_scene_dialog = NewSceneDialog.init(),
    };
}

pub fn deinit(self: *Editor) void {
    self.alloc.free(self.game_root_dir);
    self.entity_defs.deinit(self.alloc);
    self.entity_handles.deinit(self.alloc);
}

// 3. New helper to draw global overlays (called from main.zig)
pub fn drawOverlays(self: *Editor) void {
    self.new_scene_dialog.draw();
}

/// Adds a definition and spawns it into the world. `def` borrows its strings;
/// keep them alive for as long as the editor and world use them.
pub fn addEntity(self: *Editor, def: EntityDef) !void {
    // Reserve first: after a successful spawn nothing below can fail, so the
    // definition list and the world never get out of step.
    try self.entity_defs.ensureUnusedCapacity(self.alloc, 1);
    try self.entity_handles.ensureUnusedCapacity(self.alloc, 1);

    const handle = if (self.world) |world|
        world.spawn(def) catch |err| {
            log.err("Failed to spawn entity: {s}", .{@errorName(err)});
            return err;
        }
    else
        EntityHandle.invalid;

    self.entity_defs.appendAssumeCapacity(def);
    self.entity_handles.appendAssumeCapacity(handle);
    self.dirty = true;
}

/// Replaces definition `idx` and applies it to the entity spawned for it. The
/// entity is found by its handle, so renames and duplicate names are safe.
pub fn updateEntity(self: *Editor, idx: usize, def: EntityDef) !void {
    if (idx >= self.entity_defs.items.len) return;

    if (self.world) |world| {
        const handle = self.entity_handles.items[idx];
        if (world.get(handle)) |entity| {
            // Goes through the world so lookup by name follows the rename.
            _ = try world.setName(handle, def.name);
            entity.body = zixel.World.bodyFromDef(def);
            entity.sprite = def.sprite;
            entity.tags = def.tags;
            entity.owner = def.owner;
        }
    }

    self.entity_defs.items[idx] = def;
    self.dirty = true;
}

test "definitions stay aligned with the entities spawned for them" {
    const alloc = std.testing.allocator;
    var world = zixel.World.init(alloc);
    defer world.deinit();
    var editor = try Editor.init(alloc, "project");
    defer editor.deinit();
    editor.world = &world;

    try editor.addEntity(.{ .name = "Crate", .position = .{ .x = 1, .y = 2 } });
    try editor.addEntity(.{ .name = "Crate", .body = .{ .shape = zixel.PhysicsShape.circ(4), .mass = 2 } });
    try std.testing.expectEqual(@as(usize, 2), world.entityCount());

    // Rename the first one and give it a body; the duplicate name is untouched.
    try editor.updateEntity(0, .{
        .name = "Barrel",
        .position = .{ .x = 5, .y = 6 },
        .body = .{ .shape = zixel.PhysicsShape.rect(10, 10), .mass = 3 },
    });
    const barrel = world.getByName("Barrel").?;
    try std.testing.expect(barrel == world.get(editor.entity_handles.items[0]).?);
    try std.testing.expectEqual(@as(f32, 5), barrel.body.position.x);
    try std.testing.expectEqual(@as(f32, 3), barrel.body.mass);
    try std.testing.expectEqual(zixel.BodyKind.dynamic, barrel.body.kind);
    try std.testing.expect(world.getByName("Crate") == world.get(editor.entity_handles.items[1]).?);
    try std.testing.expectEqualStrings("Barrel", editor.entity_defs.items[0].name.?);

    // Out-of-range updates are ignored.
    try editor.updateEntity(9, .{});
    try std.testing.expectEqual(@as(usize, 2), editor.entity_defs.items.len);
}
