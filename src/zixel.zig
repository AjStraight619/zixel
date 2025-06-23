pub const engine = @import("engine/engine.zig");
pub const physics = @import("physics/world.zig");
pub const gui = @import("gui/gui_manager.zig");

// Input system
pub const input = struct {
    pub const KeybindManager = @import("input/keybinds.zig").KeybindManager;
    pub const InputBehavior = @import("input/keybinds.zig").InputBehavior;
    pub const Key = @import("input/keys.zig").Key;
};

// Utilities
pub const assets = @import("assets/assets.zig");
pub const logging = @import("core/logging.zig");

// Re-export commonly used types
pub const Engine = engine.Engine;
pub const EngineConfig = engine.EngineConfig;
pub const Scene = @import("engine/scene.zig").Scene;
pub const SceneContext = @import("engine/scene.zig").SceneContext;
pub const WindowConfig = @import("graphics/window.zig").WindowConfig;
pub const PhysicsWorld = physics.PhysicsWorld;
pub const PhysicsConfig = @import("physics/world.zig").PhysicsConfig;
pub const GUI = gui.GUI;

// Physics types
pub const Body = @import("physics/body.zig").Body;
pub const DynamicBody = @import("physics/body.zig").DynamicBody;
pub const StaticBody = @import("physics/body.zig").StaticBody;
pub const PhysicsShape = @import("math/shapes.zig").PhysicsShape;

// Camera types
pub const Camera = @import("graphics/camera.zig").Camera;
pub const CameraConfig = @import("graphics/camera.zig").CameraConfig;
pub const CameraType = @import("graphics/camera.zig").CameraType;
pub const CameraBounds = @import("graphics/camera.zig").CameraBounds;

// Going to try to keep reaylib our of the public api once we wrap all the functions we need
// For now it is just for convenience
pub const rl = @import("raylib");
pub const Vector2 = rl.Vector2;
pub const Rectangle = rl.Rectangle;
pub const Color = rl.Color;
