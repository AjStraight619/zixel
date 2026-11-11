const std = @import("std");
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;
const EntityDef = zixel.EntityDef;
const log = std.log.scoped(.zixel_editor);

const NewSceneDialog = @import("toolbar/file/NewSceneDialog.zig");

const Editor = @This();

alloc: Allocator,

world: ?*zixel.World = null,

// 1. Editor owns the dialog state
new_scene_dialog: NewSceneDialog,

selected_entity: ?usize = null,

game_root_dir: []const u8,

show_scene_view: bool = true,
show_hierarchy: bool = true,
show_inspector: bool = true,
show_console: bool = true,
show_demo: bool = false,

entity_defs: std.ArrayList(EntityDef),
dirty: bool = false,
scene_file_path: ?[]const u8 = null,

pub fn init(alloc: Allocator, root_path: []const u8) !Editor {
    const root_copy = try alloc.dupe(u8, root_path);

    return .{
        .alloc = alloc,
        .entity_defs = .empty,
        .game_root_dir = root_copy,
        // 2. Initialize dialog
        .new_scene_dialog = NewSceneDialog.init(),
    };
}

pub fn deinit(self: *Editor) void {
    self.alloc.free(self.game_root_dir);
    self.entity_defs.deinit(self.alloc);
}

// 3. New helper to draw global overlays (called from main.zig)
pub fn drawOverlays(self: *Editor) void {
    self.new_scene_dialog.draw();
}

pub fn addEntity(self: *Editor, def: EntityDef) !void {
    if (self.world) |world| {
        _ = world.spawn(def) catch |err| {
            log.err("Failed to spawn entity: {s}", .{@errorName(err)});
            return err;
        };
    }
    try self.entity_defs.append(self.alloc, def);
    self.dirty = true;
}

pub fn updateEntity(self: *Editor, idx: usize, def: EntityDef) void {
    if (idx >= self.entity_defs.items.len) return;

    self.entity_defs.items[idx] = def;

    if (self.world) |world| {
        if (def.name) |n| {
            if (world.getByName(n)) |entity| {
                entity.body.position = def.position;
                entity.body.rotation = def.rotation;
                entity.body.mass = def.body.mass;
                entity.body.friction = def.body.friction;
                entity.body.restitution = def.body.restitution;
                entity.body.velocity = def.body.velocity;
                entity.body.inertia = def.body.inertia;
                entity.body.shape = def.body.shape;
                entity.body.kind = def.body.kind;
                entity.sprite = def.sprite;
                entity.tags = def.tags;
                entity.owner = def.owner;
                entity.name = def.name;
            }
        }
    }
    self.dirty = true;
}
