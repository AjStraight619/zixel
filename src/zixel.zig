// Main library exports
pub const engine = @import("engine/engine.zig");
pub const physics = @import("physics/world.zig");
pub const gui = @import("gui/gui_manager.zig");
pub const input = @import("input/input_manager.zig");
pub const assets = @import("assets/assets.zig");
pub const logging = @import("core/logging.zig");

// Export main engine components
pub const Engine = @import("engine/engine.zig").Engine;
pub const EngineConfig = @import("engine/engine.zig").EngineConfig;

pub const rl = @import("raylib");
pub const Vector2 = rl.Vector2;
pub const Rectangle = rl.Rectangle;

pub const utils = @import("math/utils.zig");

pub const Body = @import("physics/body.zig").Body;
pub const DynamicBody = @import("physics/body.zig").DynamicBody;
pub const StaticBody = @import("physics/body.zig").StaticBody;
pub const PhysicsShape = @import("math/shapes.zig").PhysicsShape;
pub const GameAction = @import("input/keybinds.zig").GameAction;
