pub const engine = @import("engine/engine.zig");
pub const physics = @import("physics/world.zig");

// Export main engine components
pub const Engine = @import("engine/engine.zig").Engine;
pub const PhysicsTestRunner = @import("engine/engine.zig").PhysicsTestRunner;

pub const rl = @import("raylib");
pub const Vector2 = rl.Vector2;
pub const Rectangle = rl.Rectangle;

pub const Body = @import("physics/body.zig").Body;
pub const DynamicBody = @import("physics/body.zig").DynamicBody;
pub const StaticBody = @import("physics/body.zig").StaticBody;
pub const GameAction = @import("input/keybinds.zig").GameAction;
