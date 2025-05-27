pub const engine = @import("engine/engine.zig");
pub const physics = @import("physics/world.zig");

// Use Raylib's math types directly
// Assuming 'rl' will be how raylib is typically imported in files that use these.
// Or, we can point directly to the raylib-zig package path if known and stable.
// For now, let's expect users of root.zig to have `const rl = @import("raylib");`
pub const rl = @import("raylib"); // Make raylib itself accessible for direct use
pub const Vector2 = rl.Vector2;
pub const Rectangle = rl.Rectangle;
// Circle is not a top-level struct in Raylib in the same way, handle in consuming code.

pub const Body = @import("physics/body.zig").Body;
pub const DynamicBody = @import("physics/body.zig").DynamicBody;
pub const StaticBody = @import("physics/body.zig").StaticBody;
pub const GameAction = @import("input/keybinds.zig").GameAction;
