//! Shared runtime API for games and the editor.
// Public namespaces mirror their source directories.
pub const engine = @import("engine.zig");
pub const core = @import("core.zig");
pub const physics = @import("physics.zig");
pub const math = @import("math.zig");
pub const logging = @import("logging.zig");

pub const Engine = engine.Engine;
pub const Ctx = engine.Ctx;

pub const Input = engine.Input;
pub const Renderer = engine.Renderer;
pub const Renderable = engine.Renderable;
pub const Scene = engine.Scene;
pub const Sprite = engine.Sprite;

// Entity system
pub const Entity = engine.Entity;
pub const EntityDef = engine.EntityDef;
pub const OwnedEntityDef = engine.OwnedEntityDef;
pub const EntityHandle = engine.EntityHandle;

// Convenience exports
pub const Vec2 = math.Vec2;
pub const Color = engine.Color;
pub const World = engine.World;
pub const Physics = physics.Physics;
pub const drawEntities = engine.drawEntities;
pub const Body = physics.Body;
pub const BodyKind = physics.BodyKind;
pub const PhysicsShape = physics.PhysicsShape;
pub const Key = Input.Key;
pub const MouseButton = Input.MouseButton;

test {
    _ = logging;
    _ = @import("engine/world_physics_test.zig");
    _ = @import("core/nav/astar.zig");
    _ = @import("physics/response.zig");
    _ = @import("physics/narrowphase.zig");
    _ = @import("engine/data.zig");
    _ = @import("engine/Entity.zig");
    _ = @import("engine/World.zig");
}
