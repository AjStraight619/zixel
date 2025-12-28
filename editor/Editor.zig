const std = @import("std");
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;
const EntityDef = zixel.EntityDef;

const Editor = @This();

alloc: Allocator,

world: ?*zixel.World = null,

selected_entity: ?usize = null,

show_scene_view: bool = true,
show_hierarchy: bool = true,
show_inspector: bool = true,
show_console: bool = true,
show_demo: bool = false,

console_lines: std.ArrayList([]const u8),

scene_file_path: ?[]const u8 = null,
entity_defs: std.ArrayList(EntityDef),
dirty: bool = false,

pub fn init(alloc: Allocator) Editor {
    return .{
        .alloc = alloc,
        .console_lines = .empty,
        .entity_defs = .empty,
    };
}

pub fn deinit(self: *Editor) void {
    self.console_lines.deinit(self.alloc);
}

pub fn addEntity(self: *Editor, def: EntityDef) !void {
    // Spawn entity in the world
    // TODO: Add proper error handling here
    if (self.world) |world| {
        _ = world.spawn(def) catch |err| {
            self.log("Failed to spawn entity: {s}", .{@errorName(err)});
        };
    }

    // Store def for save
    try self.entity_defs.append(self.alloc, def);
    self.dirty = true;
}

pub fn updateEntity(self: *Editor, idx: usize, def: EntityDef) void {
    if (idx >= self.entity_defs.items.len) return;

    self.entity_defs.items[idx] = def;

    // Sync changes to world if entity exists
    if (self.world) |world| {
        if (def.name) |name| {
            if (world.getByName(name)) |entity| {
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

pub fn log(self: *Editor, msg: []const u8) void {
    // In a real app, you'd dup this string, but for now just storing the slice
    self.console_lines.append(self.alloc, msg) catch {};
}

pub fn clearLog(self: *Editor) void {
    self.console_lines.clearRetainingCapacity();
}
