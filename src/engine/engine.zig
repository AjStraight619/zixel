const std = @import("std");
const rl = @import("raylib");
const Allocator = std.mem.Allocator;
const Window = @import("../graphics/window.zig").Window;
const WindowConfig = @import("../graphics/window.zig").WindowConfig;
const PhysicsConfig = @import("../physics/config.zig").PhysicsConfig;
const PhysicsWorld = @import("../physics/world.zig").PhysicsWorld;
const Assets = @import("../assets/assets.zig").Assets;
const keybinds = @import("../input/keybinds.zig");
const GUIManager = @import("../gui/gui_manager.zig").GUI;
const inputManager = @import("../input/input_manager.zig");
const InputManager = inputManager.InputManager;
const GuiAction = inputManager.GuiAction;
const Body = @import("../physics/body.zig").Body;

pub const EngineConfig = struct {
    window: WindowConfig = .{},
    physics: PhysicsConfig = .{},
    target_fps: u32 = 60,
    load_default_keybinds: bool = true,
    assets_base_path: [:0]const u8 = "assets/",
};

pub const HandleInputFn = *const fn (engine: *Engine, alloc: Allocator) anyerror!void;
pub const UpdateFn = *const fn (engine: *Engine, alloc: Allocator, dt: f32) anyerror!void;
pub const RenderFn = *const fn (engine: *Engine, alloc: Allocator) anyerror!void;
pub const Collision_Callback = *const fn (engine: *Engine, alloc: Allocator, body1: *Body, body2: *Body) anyerror!void;

pub const Engine = struct {
    alloc: Allocator,
    window: Window,
    physics: PhysicsWorld,
    input_manager_ptr: ?*anyopaque = null,
    target_fps: u32,
    assets: Assets,
    gui: GUIManager,
    // Should require the user to have these.  @compiileError if they dont have these implemented
    update_game: ?UpdateFn = null,
    render_game: ?RenderFn = null,
    collision_callback: ?Collision_Callback = null,

    const Self = @This();

    pub fn init(alloc: Allocator, config: EngineConfig) Self {
        const window = Window.init(config.window);
        const assets = Assets.init(alloc, config.assets_base_path);
        const gui = GUIManager.init(alloc, &window);
        const physics = PhysicsWorld.init(alloc, config.physics);

        rl.setTargetFPS(@intCast(config.target_fps));

        return Self{
            .alloc = alloc,
            .window = window,
            .physics = physics,
            .target_fps = config.target_fps,
            .assets = assets,
            .gui = gui,
        };
    }

    pub fn deinit(self: *Self) void {
        self.window.deinit();
        self.physics.deinit();
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
        const physics_dt = self.physics.getPhysicsTimeStep();

        while (!rl.windowShouldClose()) {
            const frame_time = rl.getFrameTime();
            accumulator += frame_time;

            // Physics simulation with fixed timestep
            while (accumulator >= physics_dt) {
                self.physics.update(self, physics_dt);
                if (self.update_game) |update_fn_ptr| {
                    try update_fn_ptr(self, self.alloc, physics_dt);
                }
                accumulator -= physics_dt;
            }

            // Rendering
            rl.beginDrawing();
            rl.clearBackground(rl.Color.white);
            if (self.render_game) |render_fn_ptr| {
                try render_fn_ptr(self, self.alloc);
            }

            self.gui.update(self);

            rl.endDrawing();
        }
    }

    pub fn enableDebugDrawing(self: *Self, aabb: bool, contacts: bool, joints: bool) void {
        self.physics.config.debug_draw_aabb = aabb;
        self.physics.config.debug_draw_contacts = contacts;
        self.physics.config.debug_draw_joints = joints;
    }

    pub fn getInputManager(self: *Self, comptime T: type) *T {
        return @ptrCast(@alignCast(self.input_manager_ptr.?));
    }

    pub fn setInputManager(self: *Self, manager: anytype) void {
        self.input_manager_ptr = @ptrCast(@alignCast(manager));
    }

    /// Render physics debug information (AABBs, contacts, joints)
    pub fn debugRenderPhysics(self: *Self) void {
        self.physics.debugRender();
    }

    pub fn toggleDebugPanel(self: *Self) void {
        self.gui.toggleDebugPanel();
    }
};
