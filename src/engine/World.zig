//! Entity storage, lookup, and lifetime. Simulation and drawing are separate.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Vec2 = @import("../math/Vec2.zig");
const Body = @import("../physics/Body.zig");
const BodyOptions = Body.BodyOptions;
const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
pub const Entity = @import("Entity.zig");
pub const EntityDef = Entity.EntityDef;
pub const EntityHandle = Entity.EntityHandle;
pub const EntitySlot = @import("EntitySlot.zig");
const World = @This();

alloc: Allocator,
slots: std.ArrayList(EntitySlot) = .empty,
free_indices: std.ArrayList(u32) = .empty,
name_index: std.StringHashMap(EntityHandle),

pub fn init(alloc: Allocator) World {
    return .{ .alloc = alloc, .name_index = std.StringHashMap(EntityHandle).init(alloc) };
}

pub fn deinit(self: *World) void {
    self.name_index.deinit();
    self.slots.deinit(self.alloc);
    self.free_indices.deinit(self.alloc);
}

/// Borrowed iterator; spawning/removing entities invalidates it and its pointers.
pub const BodyIterator = struct {
    slots: []EntitySlot,
    index: usize = 0,

    pub fn next(self: *BodyIterator) ?*Body {
        while (self.index < self.slots.len) {
            const slot = &self.slots[self.index];
            self.index += 1;
            if (slot.alive) return &slot.entity.body;
        }
        return null;
    }
};

pub fn bodies(self: *World) BodyIterator {
    return .{ .slots = self.slots.items };
}

/// Spawn an entity from a borrowed definition. The caller must keep its strings
/// alive until this entity is removed from the world.
///
/// Names are not required to be unique: `getByName` returns the most recently
/// spawned live entity with that name.
pub fn spawn(self: *World, def: EntityDef) !EntityHandle {
    const entity = Entity{
        .name = def.name,
        .tags = def.tags,
        .owner = def.owner,
        .body = bodyFromDef(def),
        .sprite = def.sprite,
    };

    // Reserve the index entry first so a failure cannot leave a live entity
    // that is missing from the name index.
    if (def.name != null) try self.name_index.ensureUnusedCapacity(1);

    // Insert into slot storage
    const handle = try self.insertEntity(entity);

    // Index by name for fast lookup
    if (def.name) |n| self.name_index.putAssumeCapacity(n, handle);

    return handle;
}

/// The physics body a definition describes. Definitions without a body get a
/// 1x1 static placeholder at their position.
pub fn bodyFromDef(def: EntityDef) Body {
    const b = def.body orelse return Body.initStatic(PhysicsShape.rect(1, 1), def.position, .{});
    const opts = BodyOptions{
        .rotation = def.rotation,
        .restitution = b.restitution,
        .friction = b.friction,
        .velocity = b.velocity,
        .mass = b.mass,
        .inertia = b.inertia,
    };
    return switch (b.kind) {
        .static => Body.initStatic(b.shape, def.position, opts),
        .dynamic => Body.initDynamic(b.shape, def.position, opts),
        .kinematic => Body.initKinematic(b.shape, def.position, opts),
    };
}

/// Rename an entity and keep name lookup in step. `name` is borrowed, like the
/// strings passed to `spawn`. Returns false if the handle is stale or invalid.
pub fn setName(self: *World, handle: EntityHandle, name: ?[]const u8) !bool {
    const entity = self.get(handle) orelse return false;
    if (name != null) try self.name_index.ensureUnusedCapacity(1);
    if (entity.name) |old| {
        if (self.name_index.get(old)) |indexed| {
            if (indexed.eql(handle)) _ = self.name_index.remove(old);
        }
    }
    entity.name = name;
    if (name) |n| self.name_index.putAssumeCapacity(n, handle);
    return true;
}

/// Remove one entity. Returns false if the handle is stale or invalid.
pub fn remove(self: *World, handle: EntityHandle) bool {
    if (self.get(handle) == null) return false;
    self.removeSlot(handle.index);
    return true;
}

fn removeSlot(self: *World, index: u32) void {
    const slot = &self.slots.items[index];
    if (slot.entity.name) |name| {
        // Another live entity may share this name and own the index entry.
        if (self.name_index.get(name)) |indexed| {
            if (indexed.index == index and indexed.generation == slot.generation) {
                _ = self.name_index.remove(name);
            }
        }
    }
    slot.alive = false;
    slot.generation +%= 1;
    // insertEntity keeps room for every slot, so this cannot fail.
    self.free_indices.appendAssumeCapacity(index);
}

/// Get entity by name
pub fn getByName(self: *World, name: []const u8) ?*Entity {
    if (self.name_index.get(name)) |handle| {
        return self.get(handle);
    }
    return null;
}

/// Get entity by handle
pub fn get(self: *World, handle: EntityHandle) ?*Entity {
    if (handle.index >= self.slots.items.len) return null;
    const slot = &self.slots.items[handle.index];
    if (!slot.alive or slot.generation != handle.generation) return null;
    return &slot.entity;
}

/// Get entity by handle (const version)
pub fn getConst(self: *const World, handle: EntityHandle) ?*const Entity {
    if (handle.index >= self.slots.items.len) return null;
    const slot = &self.slots.items[handle.index];
    if (!slot.alive or slot.generation != handle.generation) return null;
    return &slot.entity;
}

/// Remove all entities owned by a specific scene
pub fn removeByOwner(self: *World, owner: Entity.Owner) void {
    for (self.slots.items, 0..) |*slot, i| {
        if (!slot.alive) continue;

        const matches = switch (owner) {
            .none => slot.entity.owner == .none,
            .scene => |scene_name| switch (slot.entity.owner) {
                .scene => |s| std.mem.eql(u8, s, scene_name),
                .none => false,
            },
        };

        if (matches) self.removeSlot(@intCast(i));
    }
}

/// Clear all entities (except persistent ones if keep_persistent is true)
pub fn clearAll(self: *World, keep_persistent: bool) void {
    for (self.slots.items, 0..) |*slot, i| {
        if (!slot.alive) continue;

        if (keep_persistent and slot.entity.owner == .none) continue;

        self.removeSlot(@intCast(i));
    }
}

/// Count entities
pub fn entityCount(self: *const World) usize {
    var count: usize = 0;
    for (self.slots.items) |slot| {
        if (slot.alive) count += 1;
    }
    return count;
}

fn insertEntity(self: *World, entity: Entity) !EntityHandle {
    if (self.free_indices.pop()) |free_index| {
        const slot = &self.slots.items[free_index];
        slot.entity = entity;
        slot.alive = true;
        return EntityHandle{ .index = free_index, .generation = slot.generation };
    }

    const index: u32 = @intCast(self.slots.items.len);
    // Keep room to record every slot as free, so removal never allocates.
    try self.free_indices.ensureTotalCapacity(self.alloc, self.slots.items.len + 1);
    try self.slots.append(self.alloc, EntitySlot{
        .entity = entity,
        .generation = 1,
        .alive = true,
    });

    return EntityHandle{ .index = index, .generation = 1 };
}

// ============================================================================
// Legacy body API (for compatibility - wraps entity API)
// ============================================================================

/// Legacy: add a raw body (creates entity with no name/sprite)
pub fn addBody(self: *World, body: Body) !EntityHandle {
    return self.insertEntity(Entity{ .body = body });
}

/// Legacy: get body by handle
pub fn getBody(self: *World, handle: EntityHandle) ?*Body {
    if (self.get(handle)) |entity| {
        return &entity.body;
    }
    return null;
}

/// Legacy: clear all bodies
pub fn clearBodies(self: *World) void {
    self.clearAll(false);
}

/// Legacy convenience constructors
pub fn addStaticRect(self: *World, x: f32, y: f32, w: f32, h: f32, opts: BodyOptions) !EntityHandle {
    return self.addBody(Body.initStatic(PhysicsShape.rect(w, h), Vec2.init(x, y), opts));
}

pub fn addDynamicRect(self: *World, x: f32, y: f32, w: f32, h: f32, opts: BodyOptions) !EntityHandle {
    return self.addBody(Body.initDynamic(PhysicsShape.rect(w, h), Vec2.init(x, y), opts));
}

pub fn addKinematicRect(self: *World, x: f32, y: f32, w: f32, h: f32, opts: BodyOptions) !EntityHandle {
    return self.addBody(Body.initKinematic(PhysicsShape.rect(w, h), Vec2.init(x, y), opts));
}

pub fn addStaticCircle(self: *World, x: f32, y: f32, radius: f32, opts: BodyOptions) !EntityHandle {
    return self.addBody(Body.initStatic(PhysicsShape.circ(radius), Vec2.init(x, y), opts));
}

pub fn addDynamicCircle(self: *World, x: f32, y: f32, radius: f32, opts: BodyOptions) !EntityHandle {
    return self.addBody(Body.initDynamic(PhysicsShape.circ(radius), Vec2.init(x, y), opts));
}

pub fn addKinematicCircle(self: *World, x: f32, y: f32, radius: f32, opts: BodyOptions) !EntityHandle {
    return self.addBody(Body.initKinematic(PhysicsShape.circ(radius), Vec2.init(x, y), opts));
}

test "removed entity handles stay invalid when slots are reused" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    const first = try world.addDynamicRect(0, 0, 10, 10, .{});
    const second = try world.addStaticRect(0, 0, 10, 10, .{});
    world.clearAll(false);
    _ = try world.addDynamicRect(0, 0, 10, 10, .{});
    try std.testing.expect(world.get(first) == null);
    try std.testing.expect(world.get(second) == null);
    var iter = world.bodies();
    try std.testing.expect(iter.next() != null);
    try std.testing.expect(iter.next() == null);
}

test "entities sharing a name do not break lookup when one of them is removed" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    const first = try world.spawn(.{ .name = "Enemy", .owner = .{ .scene = "A" } });
    const second = try world.spawn(.{ .name = "Enemy", .owner = .{ .scene = "B" } });
    // The newest entity owns the name; removing the older one must not unindex it.
    world.removeByOwner(.{ .scene = "A" });
    try std.testing.expect(world.get(first) == null);
    try std.testing.expect(world.getByName("Enemy") == world.get(second).?);
    try std.testing.expect(world.remove(second));
    try std.testing.expect(world.getByName("Enemy") == null);
    try std.testing.expect(!world.remove(second));
}

fn spawnAndRemoveWithFailures(alloc: Allocator) !void {
    var world = World.init(alloc);
    defer world.deinit();
    for (0..8) |_| _ = try world.spawn(.{ .name = "Named" });
    const before = world.entityCount();
    world.clearAll(false);
    // Every removed slot is reusable: respawning does not grow slot storage.
    for (0..before) |_| _ = try world.spawn(.{});
    try std.testing.expectEqual(before, world.slots.items.len);
}

test "spawning and removing stay consistent under allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, spawnAndRemoveWithFailures, .{});
}

test "renaming an entity moves its name lookup" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    const handle = try world.spawn(.{ .name = "Old" });
    try std.testing.expect(try world.setName(handle, "New"));
    try std.testing.expect(world.getByName("Old") == null);
    try std.testing.expect(world.getByName("New") == world.get(handle).?);
    try std.testing.expect(try world.setName(handle, null));
    try std.testing.expect(world.getByName("New") == null);
    try std.testing.expect(!try world.setName(EntityHandle.invalid, "Nobody"));
}
