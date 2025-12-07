const std = @import("std");
const Vec2 = @import("../math/vec2.zig");
const Body = @import("body.zig");
const Allocator = std.mem.Allocator;

pub const World = @This();

cfg: Config = DefaultPhysicsConfig,
slots: std.ArrayList(Body.BodySlot) = .empty,
free_list: std.ArrayList(u32) = .empty,
alloc: Allocator,

pub const Config = struct {
    gravity: Vec2 = .{ .x = 0, .y = -9.81 },
    // TODO: fps options
};

pub const DefaultPhysicsConfig = Config{};

pub fn init(alloc: Allocator, cfg: ?Config) World {
    return .{
        .alloc = alloc,
        .cfg = cfg orelse DefaultPhysicsConfig,
        .slots = .empty,
        .free_list = .empty,
    };
}

pub fn createStaticBody(self: *World, pos: Vec2) !Body.BodyHandle {
    // allocate a slot index
    const idx = try self.allocSlot();

    var slot = &self.slots.items[idx];

    // store the actual body in the slot
    slot.body = Body.Body{ .static = .{
        .pos = pos,
    } };

    return .{
        .idx = @intCast(idx),
        .generation = slot.generation,
    };
}

pub fn createKinematicBody(self: *World, pos: Vec2, vel: Vec2) !Body.BodyHandle {
    const idx = try self.allocSlot();

    var slot = &self.slots.items[idx];

    slot.body = Body.Body{ .kinematic = .{
        .pos = pos,
        .vel = vel,
    } };

    return .{
        .idx = @intCast(idx),
        .generation = slot.generation,
    };
}

pub fn createDynamicBody(self: *World, data: Body.DynamicBodyData) !Body.BodyHandle {
    const idx = try self.allocSlot();

    var slot = &self.slots.items[idx];

    slot.body = Body.Body{ .dynamic = data };

    return .{
        .idx = @intCast(idx),
        .generation = slot.generation,
    };
}

fn allocSlot(self: *World) !usize {
    if (self.free_list.items.len > 0) {
        return self.free_list.pop();
    }

    // grow slots
    try self.slots.append(.{
        .generation = 0,
        .body = null,
    });

    return self.slots.items.len - 1;
}
