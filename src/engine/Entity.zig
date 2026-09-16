const std = @import("std");
const Allocator = std.mem.Allocator;
const Vec2 = @import("../math/Vec2.zig");
const Color = @import("Renderer.zig").Color;
const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
const body_mod = @import("../physics/Body.zig");
const Body = body_mod;
const BodyKind = body_mod.BodyKind;
const BodyOptions = body_mod.BodyOptions;

const Entity = @This();

name: ?[]const u8 = null,

tags: []const []const u8 = &.{},

/// Who owns this entity - determines cleanup behavior
owner: Owner = .none,

/// Physics body (handles position, velocity, collision)
body: Body,

/// Optional visual
sprite: ?SpriteData = null,

pub const Owner = union(enum) {
    /// Persistent - survives scene changes
    none,
    /// Owned by a scene - removed when scene deinits
    scene: []const u8,
};

pub const SpriteData = struct {
    color: Color = Color.white,
    texture_path: ?[]const u8 = null,
};

/// Creates an owned snapshot for serialization. Call deinit on the result.
pub fn toDef(self: Entity, alloc: Allocator) !OwnedEntityDef {
    const def = EntityDef{
        .name = self.name,
        .tags = self.tags,
        .owner = self.owner,
        .position = self.body.position,
        .rotation = self.body.rotation,
        .body = .{
            .kind = self.body.kind,
            .shape = self.body.shape,
            .mass = self.body.mass,
            .friction = self.body.friction,
            .restitution = self.body.restitution,
            .velocity = self.body.velocity,
            .inertia = self.body.inertia,
        },
        .sprite = self.sprite,
    };
    return def.clone(alloc);
}

/// Borrowed description for spawning or saving an entity. Strings may be literals.
/// The caller keeps referenced data alive while the definition or spawned entity uses it.
pub const EntityDef = struct {
    name: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
    owner: Entity.Owner = .none,
    position: Vec2 = Vec2.zero,
    rotation: f32 = 0,
    body: ?BodyDef = null,
    sprite: ?Entity.SpriteData = null,

    pub const BodyDef = struct {
        kind: BodyKind = .dynamic,
        shape: PhysicsShape,
        mass: f32 = 1.0,
        friction: f32 = 0.5,
        restitution: f32 = 0.5,
        velocity: Vec2 = Vec2.zero,
        inertia: ?f32 = null,
    };

    pub fn init() EntityDef {
        return .{};
    }

    /// Deep-copies all strings into an independently owned definition.
    pub fn clone(self: EntityDef, alloc: Allocator) !OwnedEntityDef {
        var arena = std.heap.ArenaAllocator.init(alloc);
        errdefer arena.deinit();
        const storage = arena.allocator();
        var value = self;
        if (self.name) |name| value.name = try storage.dupe(u8, name);
        const tags = try storage.alloc([]const u8, self.tags.len);
        for (self.tags, 0..) |tag, i| tags[i] = try storage.dupe(u8, tag);
        value.tags = tags;
        value.owner = switch (self.owner) {
            .none => .none,
            .scene => |name| .{ .scene = try storage.dupe(u8, name) },
        };
        if (self.sprite) |sprite| {
            if (sprite.texture_path) |path| value.sprite.?.texture_path = try storage.dupe(u8, path);
        }
        return .{ .value = value, .arena = arena };
    }
};

/// Owns a snapshot's storage. Pass value to spawn/save and keep this owner alive
/// until all borrowers are finished. Transfer ownership instead of copying it.
pub const OwnedEntityDef = struct {
    value: EntityDef,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *OwnedEntityDef) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Generational handle for safely referencing entities.
pub const EntityHandle = struct {
    index: u32,
    generation: u32,

    pub const invalid = EntityHandle{
        .index = std.math.maxInt(u32),
        .generation = 0,
    };

    pub fn isValid(self: EntityHandle) bool {
        return self.index != std.math.maxInt(u32);
    }

    pub fn eql(self: EntityHandle, other: EntityHandle) bool {
        return self.index == other.index and self.generation == other.generation;
    }
};

test "entity snapshot owns strings independently of its source" {
    var name = "Player".*;
    var tag = "hero".*;
    var scene = "Level1".*;
    var texture = "hero.png".*;
    const tags = [_][]const u8{&tag};
    const entity = Entity{
        .name = &name,
        .tags = &tags,
        .owner = .{ .scene = &scene },
        .body = Body.initDynamic(PhysicsShape.rect(10, 20), Vec2.init(30, 40), .{
            .mass = 2,
            .rotation = 0.5,
            .velocity = Vec2.init(3, 4),
        }),
        .sprite = .{ .color = Color.red, .texture_path = &texture },
    };
    var snapshot = try entity.toDef(std.testing.allocator);
    defer snapshot.deinit();
    name[0] = 'X';
    tag[0] = 'X';
    scene[0] = 'X';
    texture[0] = 'X';
    const def = snapshot.value;
    try std.testing.expectEqualStrings("Player", def.name.?);
    try std.testing.expectEqualStrings("hero", def.tags[0]);
    try std.testing.expectEqualStrings("Level1", def.owner.scene);
    try std.testing.expectEqualStrings("hero.png", def.sprite.?.texture_path.?);
    try std.testing.expectEqualDeep(entity.body.position, def.position);
    try std.testing.expectEqual(entity.body.rotation, def.rotation);
    try std.testing.expectEqualDeep(entity.body.shape, def.body.?.shape);
    try std.testing.expectEqual(entity.body.mass, def.body.?.mass);
    try std.testing.expectEqualDeep(entity.body.velocity, def.body.?.velocity);
    try std.testing.expectEqualDeep(Color.red, def.sprite.?.color);
}

fn cloneWithAllocationFailures(alloc: Allocator) !void {
    const source = EntityDef{
        .name = "Player",
        .tags = &.{ "hero", "controllable" },
        .owner = .{ .scene = "Level1" },
        .sprite = .{ .texture_path = "assets/hero.png" },
    };
    var owned = try source.clone(alloc);
    defer owned.deinit();
    try std.testing.expectEqualDeep(source, owned.value);
}

test "definition clone cleans up on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneWithAllocationFailures, .{});
}

test "empty borrowed definition can be cloned and freed" {
    const source = EntityDef.init();
    var owned = try source.clone(std.testing.allocator);
    defer owned.deinit();
    try std.testing.expectEqualDeep(source, owned.value);
}
