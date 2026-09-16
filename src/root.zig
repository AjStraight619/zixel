pub const Engine = @import("engine/Engine.zig");
pub const Ctx = @import("engine/Ctx.zig");

pub const Input = @import("engine/Input.zig");
pub const Renderer = @import("engine/Renderer.zig");
pub const Renderable = @import("engine/Renderable.zig");
pub const Scene = @import("engine/Scene.zig");
pub const Sprite = @import("engine/Sprite.zig");

// Entity system
pub const Entity = @import("engine/Entity.zig");
pub const EntityDef = @import("engine/Entity.zig").EntityDef;
pub const OwnedEntityDef = @import("engine/Entity.zig").OwnedEntityDef;
pub const EntityHandle = @import("engine/Entity.zig").EntityHandle;

// Core (pure libs / algorithms)
pub const core = struct {
    pub const nav = struct {
        pub const Grid = @import("core/nav/Grid.zig");
        pub const astar = @import("core/nav/astar.zig");
        pub const Nav = @import("core/nav/Nav.zig");
    };
};

// Physics
pub const physics = struct {
    pub const World = @import("physics/World.zig");
    pub const Body = @import("physics/Body.zig");
    pub const BodyKind = @import("physics/Body.zig").BodyKind;
    pub const BodyOptions = @import("physics/Body.zig").BodyOptions;
    pub const PhysicsShape = @import("math/shapes.zig").PhysicsShape;
    pub const collision = @import("physics/collision.zig");
    pub const response = @import("physics/response.zig");
    pub const narrowphase = @import("physics/narrowphase.zig");
};

test {
    _ = @import("physics/response.zig");
    _ = @import("physics/narrowphase.zig");
    _ = @import("engine/data.zig");
    _ = @import("engine/Entity.zig");
    _ = @import("physics/World.zig");
}

// Math
pub const math = struct {
    pub const Vec2 = @import("math/Vec2.zig");
    pub const Aabb = @import("math/Aabb.zig");
    pub const shapes = @import("math/shapes.zig");
};

// Convenience exports
pub const Vec2 = math.Vec2;
pub const Color = Renderer.Color;
pub const World = physics.World;
pub const Body = physics.Body;
pub const BodyKind = physics.BodyKind;
pub const PhysicsShape = physics.PhysicsShape;
pub const Key = Input.Key;
pub const MouseButton = Input.MouseButton;
