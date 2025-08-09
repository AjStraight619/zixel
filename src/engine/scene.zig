const std = @import("std");
const Engine = @import("engine.zig").Engine;
const PhysicsWorld = @import("../physics/world.zig").PhysicsWorld;
const Assets = @import("../assets/assets.zig").Assets;
const GUIManager = @import("../gui/gui_manager.zig").GUI;
const Body = @import("../physics/body.zig").Body;
const Allocator = std.mem.Allocator;
const Camera = @import("../graphics/camera.zig").Camera;

pub const SceneContext = struct {
    engine: *Engine,
    user_data: *anyopaque,
    scene_name: []const u8,

    // Convenience accessors for engine systems
    pub inline fn physics(self: *SceneContext) ?*PhysicsWorld {
        if (self.engine.current_scene) |scene| {
            return scene.physics_world;
        }
        return null;
    }

    pub inline fn assets(self: *SceneContext) *Assets {
        return &self.engine.assets;
    }

    pub inline fn gui(self: *SceneContext) *GUIManager {
        return &self.engine.gui;
    }

    pub inline fn alloc(self: *SceneContext) Allocator {
        return self.engine.alloc;
    }

    pub inline fn switchScene(self: *SceneContext, name: []const u8) !void {
        try self.engine.switchToScene(name);
    }

    pub inline fn camera(self: *SceneContext) ?*Camera {
        if (self.engine.current_scene) |scene| {
            return scene.camera;
        }
        return null;
    }

    /// Get the currently active input manager of the specified type
    /// Useful when you have multiple input manager types but only one is active
    pub fn input(self: *SceneContext, comptime T: type) ?*T {
        return self.engine.getCurrentKeybindManager(T);
    }

    /// Get a named input manager of the specified type
    pub fn getKeybindManager(self: *SceneContext, name: []const u8, comptime T: type) ?*T {
        return self.engine.getKeybindManager(name, T);
    }

    /// Share a body with a key for scene transitions
    pub inline fn share(self: *SceneContext, key: []const u8, body: *Body) !void {
        return self.engine.share(key, body);
    }

    /// Claim a shared body by key
    pub inline fn claim(self: *SceneContext, key: []const u8) ?*Body {
        return self.engine.claim(key);
    }

    /// Create a body using the engine's allocator
    pub inline fn createBody(self: *SceneContext, body: Body) !*Body {
        return self.engine.createBody(body);
    }

    /// Destroy a body using the engine's allocator
    pub inline fn destroyBody(self: *SceneContext, body: *Body) void {
        self.engine.destroyBody(body);
    }

    // Legacy alias for backward compatibility
    pub const getInputManager = getKeybindManager;
};

pub const Scene = struct {
    context: *SceneContext,
    physics_world: ?*PhysicsWorld,
    camera: ?*Camera = null,
    auto_update_physics: bool = true,
    auto_update_camera: bool = true,
    input_manager_name: ?[]const u8 = null,

    // Core lifecycle callbacks
    init: *const fn (ctx: *SceneContext) anyerror!void,
    deinit: *const fn (ctx: *SceneContext) void,
    update: *const fn (ctx: *SceneContext, dt: f32) anyerror!void,
    render: *const fn (ctx: *SceneContext) anyerror!void,

    // Optional callbacks
    on_enter: ?*const fn (ctx: *SceneContext) anyerror!void = null,
    on_exit: ?*const fn (ctx: *SceneContext) anyerror!void = null,

    // Scene-specific collision callback
    collision_callback: ?*const fn (ctx: *SceneContext, body1: *Body, body2: *Body) anyerror!void = null,

    // Scene cleanup function
    cleanup_scene_instance: *const fn (allocator: std.mem.Allocator, user_data: *anyopaque) void,
};
