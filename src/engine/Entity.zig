const std = @import("std");
const Vec2 = @import("../math/vec2.zig");
const Color = @import("Renderer.zig").Color;
const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
const body_mod = @import("../physics/body.zig");
const Body = body_mod.Body;
const BodyKind = body_mod.BodyKind;
const BodyOptions = body_mod.BodyOptions;

pub const Entity = struct {
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
    };
};

/// Definition for spawning an entity (what you pass to world.spawn)
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
