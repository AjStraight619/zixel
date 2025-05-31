const std = @import("std");
const rl = @import("raylib");
const Window = @import("../renderer/window.zig").Window;
const WindowConfig = @import("../renderer/config.zig").WindowConfig;
const PhysicsConfig = @import("../physics/config.zig").PhysicsConfig;
const PhysicsWorld = @import("../physics/world.zig").PhysicsWorld;
const Assets = @import("../assets/assets.zig").Assets;
const keybinds = @import("../input/keybinds.zig");
const GUIManager = @import("../gui/gui_manager.zig").GUI;
const InputManager = @import("../input/input_manager.zig").InputManager;

const EngineConfig = struct {
    window: WindowConfig = .{},
    physics: PhysicsConfig = .{},
    target_fps: u32 = 60,
    load_default_keybinds: bool = true,
    assets_base_path: []const u8 = "assets/",
};

pub const HandleInputFn = *const fn (engine: *Engine, allocator: std.mem.Allocator) anyerror!void;
pub const UpdateFn = *const fn (engine: *Engine, allocator: std.mem.Allocator, dt: f32) anyerror!void;
pub const RenderFn = *const fn (engine: *Engine, allocator: std.mem.Allocator) anyerror!void;

pub const Engine = struct {
    allocator: std.mem.Allocator,
    window: Window,
    physics: PhysicsWorld,
    keybind_manager: keybinds.KeybindManager,
    input_manager: InputManager,
    target_fps: u32,
    assets: Assets,
    gui: GUIManager,
    // Use optional function pointers for callback fields
    handle_input: ?HandleInputFn = null,
    update_game: ?UpdateFn = null,
    render_game: ?RenderFn = null,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, config: EngineConfig) !Self {
        var kb_manager = keybinds.KeybindManager.init(alloc);
        if (config.load_default_keybinds) {
            try kb_manager.loadDefaultBindings();
        }

        var input_manager = InputManager.init(alloc, &kb_manager);
        try input_manager.loadDefaultGuiBindings();
        const window = Window.init(config.window);
        const assets = Assets.init(alloc, config.assets_base_path);
        const gui = GUIManager.init(alloc, &window);
        const physics = PhysicsWorld.init(alloc, config.physics);

        rl.setTargetFPS(@intCast(config.target_fps));
        return Self{
            .allocator = alloc,
            .window = window,
            .physics = physics,
            .keybind_manager = kb_manager,
            .input_manager = input_manager,
            .target_fps = config.target_fps,
            .assets = assets,
            .gui = gui,
            .handle_input = null,
            .update_game = null,
            .render_game = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.window.deinit();
        self.physics.deinit();
        self.keybind_manager.deinit();
        self.input_manager.deinit();
        self.gui.deinit();
    }

    // Setter functions now accept function pointers
    pub fn setHandleInputFn(self: *Self, func: HandleInputFn) void {
        self.handle_input = func;
    }

    pub fn setUpdateFn(self: *Self, func: UpdateFn) void {
        self.update_game = func;
    }

    pub fn setRenderFn(self: *Self, func: RenderFn) void {
        self.render_game = func;
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
            // Unified input handling with priority system
            _ = try self.input_manager.handleInput(&self.gui, self.handle_input, self);

            const frame_time = rl.getFrameTime();
            accumulator += frame_time;

            // Physics simulation with fixed timestep
            while (accumulator >= physics_dt) {
                self.physics.update(physics_dt);
                if (self.update_game) |update_fn_ptr| {
                    try update_fn_ptr(self, self.allocator, physics_dt);
                }
                accumulator -= physics_dt;
            }

            // Rendering
            rl.beginDrawing();
            rl.clearBackground(rl.Color.white);
            if (self.render_game) |render_fn_ptr| {
                try render_fn_ptr(self, self.allocator);
            }

            self.gui.update(self);

            rl.endDrawing();
        }
    }

    // Input Manager methods
    pub fn getInputManager(self: *Self) *InputManager {
        return &self.input_manager;
    }

    pub fn setGuiKeybind(self: *Self, action: @import("../input/input_manager.zig").GuiAction, key: rl.KeyboardKey) !void {
        try self.input_manager.setGuiKeybind(action, key);
    }

    pub fn getKeybindManager(self: *Self) *keybinds.KeybindManager {
        return &self.keybind_manager;
    }

    // Physics configuration methods
    pub fn getPhysicsWorld(self: *Self) *PhysicsWorld {
        return &self.physics;
    }

    pub fn setGravity(self: *Self, gravity: rl.Vector2) void {
        self.physics.config.gravity = gravity;
        self.physics.gravity = gravity;
    }

    pub fn getGravity(self: *const Self) rl.Vector2 {
        return self.physics.gravity;
    }

    pub fn enableDebugDrawing(self: *Self, aabb: bool, contacts: bool, joints: bool) void {
        self.physics.config.debug_draw_aabb = aabb;
        self.physics.config.debug_draw_contacts = contacts;
        self.physics.config.debug_draw_joints = joints;
    }

    /// Render physics debug information (AABBs, contacts, joints)
    pub fn debugRenderPhysics(self: *Self) void {
        self.physics.debugRender();
    }

    pub fn getPhysicsStepCount(self: *const Self) u64 {
        return self.physics.getStepCount();
    }

    // GUI methods
    pub fn getGUI(self: *Self) *GUIManager {
        return &self.gui;
    }

    pub fn toggleDebugPanel(self: *Self) void {
        self.gui.toggleDebugPanel();
    }
};
