// Zixel - A 2D Game Engine written in Zig
// Main library exports

pub const engine = @import("engine/engine.zig");
pub const physics = @import("physics/world.zig");

// Export main engine components
pub const Engine = @import("engine/engine.zig").Engine;

pub const rl = @import("raylib");
pub const Vector2 = rl.Vector2;
pub const Rectangle = rl.Rectangle;

pub const utils = @import("core/math/utils.zig");

pub const Body = @import("physics/body.zig").Body;
pub const DynamicBody = @import("physics/body.zig").DynamicBody;
pub const StaticBody = @import("physics/body.zig").StaticBody;
pub const PhysicsShape = @import("core/math/shapes.zig").PhysicsShape;
pub const GameAction = @import("input/keybinds.zig").GameAction;

// Future ECS exports (when implemented)
// pub const World = @import("ecs/world.zig").World;
// pub const Entity = @import("ecs/entity.zig").Entity;
// pub const Component = @import("ecs/component.zig").Component;
// pub const System = @import("ecs/system.zig").System;
