const std = @import("std");
const rl = @import("raylib");
const Allocator = std.mem.Allocator;
const Window = @import("../graphics/window.zig").Window;
const WindowConfig = @import("../graphics/window.zig").WindowConfig;
const PhysicsConfig = @import("../physics/world.zig").PhysicsConfig;
const PhysicsWorld = @import("../physics/world.zig").PhysicsWorld;
const Assets = @import("../assets/assets.zig").Assets;
const keybinds = @import("../input/keybinds.zig");
const GUIManager = @import("../gui/gui_manager.zig").GUI;
const Body = @import("../physics/body.zig").Body;
const Scene = @import("scene.zig").Scene;
const SceneContext = @import("scene.zig").SceneContext;
const Camera = @import("../graphics/camera.zig").Camera;
const CameraConfig = @import("../graphics/camera.zig").CameraConfig;

pub const EngineConfig = struct {
    window: WindowConfig = .{},
    physics: PhysicsConfig = .{},
    target_fps: u32 = 60,
    load_default_keybinds: bool = true,
    assets_base_path: [:0]const u8 = "assets/",
};

// Scene management types (replaced global function pointers)
const StringHashMap = std.HashMap([]const u8, *Scene, std.hash_map.StringContext, std.hash_map.default_max_load_percentage);
const ContextHashMap = std.HashMap([]const u8, SceneContext, std.hash_map.StringContext, std.hash_map.default_max_load_percentage);

// Input manager storage (generic - can hold any KeybindManager type)
const InputManagerMap = std.HashMap([]const u8, *anyopaque, std.hash_map.StringContext, std.hash_map.default_max_load_percentage);
// Body sharing storage for scene transitions
const BodyShareMap = std.HashMap([]const u8, *Body, std.hash_map.StringContext, std.hash_map.default_max_load_percentage);

pub const Engine = struct {
    alloc: Allocator,
    window: Window,
    input_managers: InputManagerMap,
    current_input_manager: ?*anyopaque = null,
    target_fps: u32,
    assets: Assets,
    gui: GUIManager,

    // Scene management (replaces global update/render functions)
    scenes: StringHashMap,
    scene_contexts: ContextHashMap,
    current_scene: ?*Scene = null,
    next_scene_name: ?[]const u8 = null,
    persistent_bodies: std.ArrayList(*Body),

    // Physics config for creating scene physics worlds
    physics_config: PhysicsConfig,

    // Body sharing for scene transitions ("carry by key" UX)
    shared_bodies: BodyShareMap,

    const Self = @This();

    pub fn createBody(self: *Engine, body: Body) !*Body {
        const p = try self.alloc.create(Body);
        p.* = body;
        return p;
    }

    pub fn destroyBody(self: *Engine, p: *Body) void {
        self.alloc.destroy(p);
    }

    /// Share a body with a key for scene transitions
    pub fn share(self: *Engine, key: []const u8, body: *Body) !void {
        try self.shared_bodies.put(key, body);
    }

    /// Claim a shared body by key (removes it from shared storage)
    pub fn claim(self: *Engine, key: []const u8) ?*Body {
        if (self.shared_bodies.fetchRemove(key)) |entry| {
            return entry.value;
        }
        return null;
    }

    pub fn init(alloc: Allocator, config: EngineConfig) Self {
        const window = Window.init(config.window);
        const assets = Assets.init(alloc, config.assets_base_path);
        const gui = GUIManager.init(alloc, &window);

        rl.setTargetFPS(@intCast(config.target_fps));

        return Self{
            .alloc = alloc,
            .window = window,
            .target_fps = config.target_fps,
            .assets = assets,
            .gui = gui,
            .input_managers = InputManagerMap.init(alloc),
            .scenes = StringHashMap.init(alloc),
            .scene_contexts = ContextHashMap.init(alloc),
            .persistent_bodies = std.ArrayList(*Body).init(alloc),
            .physics_config = config.physics,
            .shared_bodies = BodyShareMap.init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        // Deinit current scene
        if (self.current_scene) |scene| {
            scene.deinit(scene.context);
        }

        // Cleanup all scenes and their physics worlds
        var scene_iter = self.scenes.iterator();
        while (scene_iter.next()) |entry| {
            const scene = entry.value_ptr.*;
            if (scene.physics_world) |physics_world| {
                physics_world.deinit();
                self.alloc.destroy(physics_world);
            }
            if (scene.camera) |camera| {
                self.alloc.destroy(camera);
            }
            // Clean up scene instance (user_data) using the type-specific cleanup function
            if (self.scene_contexts.get(entry.key_ptr.*)) |context| {
                scene.cleanup_scene_instance(self.alloc, context.user_data);
            }
            self.alloc.destroy(scene);
        }

        // Cleanup scene management
        self.scenes.deinit();
        self.scene_contexts.deinit();
        self.persistent_bodies.deinit();
        self.input_managers.deinit();
        self.shared_bodies.deinit();

        // Cleanup engine systems
        self.window.deinit();
        self.gui.deinit();
    }

    pub fn setTargetFPS(self: *Self, fps: u32) void {
        self.target_fps = fps;
        rl.setTargetFPS(@intCast(fps));
    }

    pub fn setBackgroundColor(self: Self, color: rl.Color) void {
        _ = self;
        _ = color;
    }

    pub fn run(self: *Self) !void {
        var accumulator: f32 = 0.0;
        const physics_dt = self.physics_config.physics_time_step;

        while (!rl.windowShouldClose()) {
            // Handle scene switching
            try self.processSceneSwitch();

            const frame_time = rl.getFrameTime();
            accumulator += frame_time;

            // Physics simulation with fixed timestep
            while (accumulator >= physics_dt) {
                // Update scene physics if scene has physics
                if (self.current_scene) |scene| {
                    if (scene.physics_world) |physics_world| {
                        physics_world.update(self, physics_dt);
                    }

                    // Update scene camera if scene has camera
                    if (scene.camera) |camera| {
                        if (scene.auto_update_camera) {
                            camera.update(physics_dt);
                        }
                    }

                    try scene.update(scene.context, physics_dt);
                }
                accumulator -= physics_dt;
            }

            // Rendering
            rl.beginDrawing();
            rl.clearBackground(rl.Color.white);

            // Render current scene
            if (self.current_scene) |scene| {
                try scene.render(scene.context);
            }

            self.gui.update(self);
            rl.endDrawing();
        }
    }

    pub fn enableDebugDrawing(self: *Self, aabb: bool, contacts: bool, joints: bool) void {
        // Update physics config for future scenes
        self.physics_config.debug_draw_aabb = aabb;
        self.physics_config.debug_draw_contacts = contacts;
        self.physics_config.debug_draw_joints = joints;

        // Update current scene's physics if it exists
        if (self.current_scene) |scene| {
            if (scene.physics_world) |physics_world| {
                physics_world.config.debug_draw_aabb = aabb;
                physics_world.config.debug_draw_contacts = contacts;
                physics_world.config.debug_draw_joints = joints;
            }
        }
    }

    /// Register a keybind manager with a name (user owns the manager)
    pub fn registerKeybindManager(self: *Self, name: []const u8, manager: anytype) !void {
        try self.input_managers.put(name, @ptrCast(@alignCast(manager)));
    }

    /// Switch to a different keybind manager
    pub fn switchToKeybindManager(self: *Self, name: []const u8) !void {
        if (self.input_managers.get(name)) |manager| {
            self.current_input_manager = manager;
        } else {
            return error.KeybindManagerNotFound;
        }
    }

    /// Get the current keybind manager (typed)
    pub fn getCurrentKeybindManager(self: *Self, comptime T: type) ?*T {
        if (self.current_input_manager) |manager| {
            return @ptrCast(@alignCast(manager));
        }
        return null;
    }

    /// Get a specific keybind manager by name (typed)
    pub fn getKeybindManager(self: *Self, name: []const u8, comptime T: type) ?*T {
        if (self.input_managers.get(name)) |manager| {
            return @ptrCast(@alignCast(manager));
        }
        return null;
    }

    /// Legacy compatibility - set current keybind manager directly
    pub fn setKeybindManager(self: *Self, manager: anytype) void {
        self.current_input_manager = @ptrCast(@alignCast(manager));
    }

    // Legacy aliases for backward compatibility
    pub const registerInputManager = registerKeybindManager;
    pub const switchToInputManager = switchToKeybindManager;
    pub const getCurrentInputManager = getCurrentKeybindManager;
    pub const getInputManager = getKeybindManager;
    pub const setInputManager = setKeybindManager;

    /// Render physics debug information (AABBs, contacts, joints)
    pub fn debugRenderPhysics(self: *Self) void {
        if (self.current_scene) |scene| {
            if (scene.physics_world) |physics_world| {
                physics_world.debugRender();
            }
        }
    }

    /// Toggle the debug panel
    pub fn toggleDebugPanel(self: *Self) void {
        self.gui.toggleDebugPanel();
    }

    /// Register a scene using comptime type reflection and interface pattern
    pub fn registerScene(self: *Self, name: []const u8, comptime SceneType: type) !void {
        // Compile-time validation for required functions
        comptime {
            if (!@hasDecl(SceneType, "init")) @compileError("Scene type must have 'init' function");
            if (!@hasDecl(SceneType, "deinit")) @compileError("Scene type must have 'deinit' function");
            if (!@hasDecl(SceneType, "update")) @compileError("Scene type must have 'update' function");
            if (!@hasDecl(SceneType, "render")) @compileError("Scene type must have 'render' function");
        }

        // Create scene instance - engine owns and manages the data
        const scene_instance = try self.alloc.create(SceneType);
        scene_instance.* = SceneType{}; // Initialize with struct defaults

        // Extract configuration from scene type (with defaults)
        const scene_config = if (@hasDecl(SceneType, "config")) SceneType.config else .{};

        // Generate type-safe wrapper functions
        const gen = struct {
            pub fn init(ctx: *SceneContext) anyerror!void {
                const scene: *SceneType = @ptrCast(@alignCast(ctx.user_data));
                return @call(.always_inline, SceneType.init, .{ scene, ctx });
            }

            pub fn deinit(ctx: *SceneContext) void {
                const scene: *SceneType = @ptrCast(@alignCast(ctx.user_data));
                return @call(.always_inline, SceneType.deinit, .{ scene, ctx });
            }

            pub fn update(ctx: *SceneContext, dt: f32) anyerror!void {
                const scene: *SceneType = @ptrCast(@alignCast(ctx.user_data));
                return @call(.always_inline, SceneType.update, .{ scene, ctx, dt });
            }

            pub fn render(ctx: *SceneContext) anyerror!void {
                const scene: *SceneType = @ptrCast(@alignCast(ctx.user_data));
                return @call(.always_inline, SceneType.render, .{ scene, ctx });
            }

            pub fn on_enter(ctx: *SceneContext) anyerror!void {
                const scene: *SceneType = @ptrCast(@alignCast(ctx.user_data));
                return @call(.always_inline, SceneType.on_enter, .{ scene, ctx });
            }

            pub fn on_exit(ctx: *SceneContext) anyerror!void {
                const scene: *SceneType = @ptrCast(@alignCast(ctx.user_data));
                return @call(.always_inline, SceneType.on_exit, .{ scene, ctx });
            }

            pub fn collision_callback(ctx: *SceneContext, body1: *Body, body2: *Body) anyerror!void {
                const scene: *SceneType = @ptrCast(@alignCast(ctx.user_data));
                return @call(.always_inline, SceneType.collision_callback, .{ scene, ctx, body1, body2 });
            }
        };

        // Create cleanup function for this specific scene type
        const cleanup_fn = struct {
            fn cleanup(allocator: std.mem.Allocator, user_data: *anyopaque) void {
                const typed_scene: *SceneType = @ptrCast(@alignCast(user_data));
                allocator.destroy(typed_scene);
            }
        }.cleanup;

        return self.registerSceneWithConfig(name, scene_instance, .{
            .needs_physics = if (@hasField(@TypeOf(scene_config), "needs_physics")) scene_config.needs_physics else true,
            .physics_config = if (@hasField(@TypeOf(scene_config), "physics_config")) scene_config.physics_config else null,
            .auto_update_physics = if (@hasField(@TypeOf(scene_config), "auto_update_physics")) scene_config.auto_update_physics else true,
            .camera_config = if (@hasField(@TypeOf(scene_config), "camera_config")) scene_config.camera_config else null,
            .auto_update_camera = if (@hasField(@TypeOf(scene_config), "auto_update_camera")) scene_config.auto_update_camera else true,
            .input_manager_name = if (@hasField(@TypeOf(scene_config), "input_manager_name")) scene_config.input_manager_name else null,
            .init = gen.init,
            .deinit = gen.deinit,
            .update = gen.update,
            .render = gen.render,
            .on_enter = if (@hasDecl(SceneType, "on_enter")) gen.on_enter else null,
            .on_exit = if (@hasDecl(SceneType, "on_exit")) gen.on_exit else null,
            .collision_callback = if (@hasDecl(SceneType, "collision_callback")) gen.collision_callback else null,
            .cleanup_scene_instance = cleanup_fn,
        });
    }

    /// Switch to a different scene
    pub fn switchToScene(self: *Self, name: []const u8) !void {
        if (!self.scenes.contains(name)) {
            return error.SceneNotFound;
        }
        self.next_scene_name = name;
    }

    /// Remove a scene from the engine
    pub fn removeScene(self: *Self, name: []const u8) void {
        if (self.scenes.get(name)) |scene| {
            if (self.current_scene == scene) {
                self.current_scene = null;
            }
            scene.deinit(scene.context);

            // Clean up scene's physics world
            if (scene.physics_world) |physics_world| {
                physics_world.deinit();
                self.alloc.destroy(physics_world);
            }

            // Clean up scene's camera
            if (scene.camera) |camera| {
                self.alloc.destroy(camera);
            }

            // Clean up scene instance (user_data)
            scene.cleanup_scene_instance(self.alloc, scene.context.user_data);

            self.alloc.destroy(scene);
            _ = self.scenes.remove(name);
            _ = self.scene_contexts.remove(name);
        }
    }

    /// Get the currently active scene
    pub fn getCurrentScene(self: *Self) ?*Scene {
        return self.current_scene;
    }

    /// Get a scene instance by name and type (for advanced scene access)
    pub fn getSceneInstance(self: *Self, name: []const u8, comptime SceneType: type) ?*SceneType {
        if (self.scenes.get(name)) |scene| {
            return @ptrCast(@alignCast(scene.context.user_data));
        }
        return null;
    }

    /// Get the current scene's physics world (for GUI and other systems)
    pub fn getCurrentPhysics(self: *Self) ?*PhysicsWorld {
        if (self.current_scene) |scene| {
            return scene.physics_world;
        }
        return null;
    }

    /// Register a new scene with the engine
    fn registerSceneWithConfig(self: *Self, name: []const u8, user_data: *anyopaque, config: struct {
        needs_physics: bool = true,
        physics_config: ?PhysicsConfig = null,
        auto_update_physics: bool = true,
        camera_config: ?CameraConfig = null,
        auto_update_camera: bool = true,
        input_manager_name: ?[]const u8 = null,
        init: *const fn (ctx: *SceneContext) anyerror!void,
        deinit: *const fn (ctx: *SceneContext) void,
        update: *const fn (ctx: *SceneContext, dt: f32) anyerror!void,
        render: *const fn (ctx: *SceneContext) anyerror!void,
        on_enter: ?*const fn (ctx: *SceneContext) anyerror!void = null,
        on_exit: ?*const fn (ctx: *SceneContext) anyerror!void = null,
        collision_callback: ?*const fn (ctx: *SceneContext, body1: *Body, body2: *Body) anyerror!void = null,
        cleanup_scene_instance: *const fn (allocator: std.mem.Allocator, user_data: *anyopaque) void,
    }) !void {
        // Create scene context
        const context = SceneContext{
            .engine = self,
            .user_data = user_data,
            .scene_name = name,
        };

        // Create scene
        const scene = try self.alloc.create(Scene);
        scene.* = Scene{
            .context = undefined, // Will be set after storing context
            .physics_world = if (config.needs_physics) try self.createScenePhysicsWorld(config.physics_config) else null,
            .camera = if (config.camera_config) |cam_config| try self.createSceneCamera(cam_config) else null,
            .auto_update_physics = config.auto_update_physics,
            .auto_update_camera = config.auto_update_camera,
            .input_manager_name = config.input_manager_name,
            .init = config.init,
            .deinit = config.deinit,
            .update = config.update,
            .render = config.render,
            .on_enter = config.on_enter,
            .on_exit = config.on_exit,
            .collision_callback = config.collision_callback,
            .cleanup_scene_instance = config.cleanup_scene_instance,
        };

        // Store context and update scene reference
        try self.scene_contexts.put(name, context);
        scene.context = self.scene_contexts.getPtr(name).?;

        // Store scene
        try self.scenes.put(name, scene);
    }

    /// Process pending scene switches (called internally by run loop)
    fn processSceneSwitch(self: *Self) !void {
        if (self.next_scene_name) |scene_name| {
            if (self.scenes.get(scene_name)) |new_scene| {
                // Exit current scene
                if (self.current_scene) |old_scene| {
                    if (old_scene.on_exit) |on_exit| {
                        try on_exit(old_scene.context);
                    }
                    old_scene.deinit(old_scene.context);

                    // Extract persistent bodies
                    try self.extractPersistentBodies();
                }

                // Add persistent bodies to new scene if it has physics
                if (new_scene.physics_world) |_| {
                    try self.addPersistentBodiesToScene();
                }

                // Switch to scene's input manager if specified
                if (new_scene.input_manager_name) |input_name| {
                    try self.switchToInputManager(input_name);
                }

                // Initialize new scene
                try new_scene.init(new_scene.context);

                // Enter new scene
                if (new_scene.on_enter) |on_enter| {
                    try on_enter(new_scene.context);
                }

                self.current_scene = new_scene;
                self.next_scene_name = null;
            }
        }
    }

    /// Create a physics world for a scene
    fn createScenePhysicsWorld(self: *Self, scene_physics_config: ?PhysicsConfig) !*PhysicsWorld {
        const physics_world = try self.alloc.create(PhysicsWorld);
        const final_config = scene_physics_config orelse self.physics_config;
        physics_world.* = PhysicsWorld.init(self.alloc, final_config);
        return physics_world;
    }

    /// Create a camera for a scene
    fn createSceneCamera(self: *Self, config: CameraConfig) !*Camera {
        const camera = try self.alloc.create(Camera);
        camera.* = Camera.init(config);
        return camera;
    }

    /// Extract persistent bodies from current physics world
    fn extractPersistentBodies(self: *Self) !void {
        if (self.current_scene) |scene| {
            if (scene.physics_world) |physics_world| {
                var i: usize = 0;
                while (i < physics_world.bodies.items.len) {
                    const body = physics_world.bodies.items[i];
                    if (body.persist) {
                        try self.persistent_bodies.append(physics_world.bodies.swapRemove(i));
                        // Don't increment i since we swapped an element
                    } else {
                        i += 1;
                    }
                }
            }
        }
    }

    /// Add persistent bodies to the current scene's physics world
    fn addPersistentBodiesToScene(self: *Self) !void {
        if (self.current_scene) |scene| {
            if (scene.physics_world) |physics_world| {
                for (self.persistent_bodies.items) |body| {
                    try physics_world.attach(body);
                }
                self.persistent_bodies.clearRetainingCapacity();
            }
        }
    }
};
