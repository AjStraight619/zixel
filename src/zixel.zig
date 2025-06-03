// Zixel - A Modern 2D Game Engine written in Zig
// Built on Entity Component System (ECS) architecture

// Core ECS engine
pub const Engine = @import("ecs/engine.zig").Engine;
pub const World = @import("ecs/world.zig").World;
pub const Entity = @import("ecs/world.zig").Entity;
pub const ComponentId = @import("ecs/world.zig").ComponentId;

// ECS components and systems
pub const components = @import("ecs/components.zig");
pub const systems = @import("ecs/systems.zig");

// GUI system
pub const gui = @import("gui/gui_manager.zig");

// Common types from raylib
pub const rl = @import("raylib");
pub const rlg = @import("raygui");
pub const Vector2 = rl.Vector2;
pub const Rectangle = rl.Rectangle;
pub const Color = rl.Color;

// Utility modules
pub const utils = @import("core/math/utils.zig");

// Legacy physics exports (still used by some systems)
pub const PhysicsShape = @import("core/math/shapes.zig").PhysicsShape;

// For convenience, re-export the main engine type at top level

// ECS module grouping for explicit imports
pub const ecs = struct {
    pub const Engine = @import("ecs/engine.zig").Engine;
    pub const World = @import("ecs/world.zig").World;
    pub const Entity = @import("ecs/world.zig").Entity;
    pub const ComponentId = @import("ecs/world.zig").ComponentId;
    pub const components = @import("ecs/components.zig");
    pub const systems = @import("ecs/systems.zig");
};
