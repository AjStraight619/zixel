const std = @import("std");
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;
const EntityDef = zixel.EntityDef;

const Editor = @This();

alloc: Allocator,

world: ?*zixel.World = null,

selected_entity: ?usize = null,

// This now stores the valid absolute path to the project
game_root_dir: []const u8,

show_scene_view: bool = true,
show_hierarchy: bool = true,
show_inspector: bool = true,
show_console: bool = true,
show_demo: bool = false,

console_lines: std.ArrayList([]const u8),

scene_file_path: ?[]const u8 = null,
entity_defs: std.ArrayList(EntityDef),
dirty: bool = false,

pub fn init(alloc: Allocator, root_path: []const u8) !Editor {
    // We duplicate the path because the original string (from main) might be temporary.
    // The Editor now "owns" this string.
    const root_copy = try alloc.dupe(u8, root_path);

    return .{
        .alloc = alloc,
        .console_lines = .empty,
        .entity_defs = .empty,
        .game_root_dir = root_copy,
    };
}

pub fn deinit(self: *Editor) void {
    // Free the path string we duplicated in init
    self.alloc.free(self.game_root_dir);

    self.console_lines.deinit(self.alloc);
    // Note: If you add more dynamic arrays (like entity_defs), deinit them here too.
    self.entity_defs.deinit(self.alloc);
}

pub fn addEntity(self: *Editor, def: EntityDef) !void {
    // Spawn entity in the world
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
        // Warning: This assumes the name hasn't changed.
        // If you change the name in the editor, this might fail to find the old entity.
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

pub fn log(self: *Editor, msg: []const u8) void {
    // For a robust log, you should dupe this string, otherwise it points to temporary memory
    const msg_copy = self.alloc.dupe(u8, msg) catch return;
    self.console_lines.append(self.alloc, msg_copy) catch {};
}

pub fn clearLog(self: *Editor) void {
    // If you dupe strings in log(), you need to free them here before clearing!
    for (self.console_lines.items) |msg| {
        self.alloc.free(msg);
    }
    self.console_lines.clearRetainingCapacity();
}
