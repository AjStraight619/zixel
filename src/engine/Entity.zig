const std = @import("std");
const Allocator = std.mem.Allocator;
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
        texture_path: ?[]const u8 = null,
    };

    /// To serialize an Entity and save to a Scene
    pub fn toDef(self: Entity, alloc: Allocator) !EntityDef {
        const name_copy = if (self.name) |n| try alloc.dupe(u8, n) else null;

        const tags_slice = try alloc.alloc([]const u8, self.tags.len);

        for (self.tags, 0..) |tag, i| {
            tags_slice[i] = try alloc.alloc(u8, tag);
        }

        const owner_copy: Owner = switch (self.owner) {
            .none => .none,
            .scene => |scene_name| .{ .scene = try alloc.dupe(u8, scene_name) },
        };

        var sprite_copy: ?Entity.SpriteData = null;
        if (self.sprite) |s| {
            sprite_copy = .{
                .color = s.color,
                .texture_path = if (s.texture_path) |p| try alloc.dupe(u8, p) else null,
            };
        }

        const body_def = EntityDef.BodyDef{
            .kind = self.body.kind,
            .shape = self.body.shape,
            .mass = self.body.mass,
            .friction = self.body.friction,
            .restitution = self.body.restitution,
            .velocity = self.body.velocity,
            .inertia = self.body.inertia,
        };

        return .{
            .name = name_copy,
            .tags = tags_slice,
            .owner = owner_copy,
            .position = self.body.position,
            .rotation = self.body.rotation,
            .body = body_def,
            .sprite = sprite_copy,
        };
    }
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

test "Entity.toDef" {}
