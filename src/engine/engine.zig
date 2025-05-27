const std = @import("std");
const rl = @import("raylib");
const Window = @import("../renderer/window.zig").Window;
const WindowConfig = @import("../renderer/config.zig").WindowConfig;
const PhysicsConfig = @import("../physics/config.zig").PhysicsConfig;
const PhysicsWorld = @import("../physics/world.zig").PhysicsWorld;
const keybinds = @import("../input/keybinds.zig");

const EngineConfig = struct {
    window: WindowConfig = .{},
    physics: PhysicsConfig = .{},
    target_fps: u32 = 60,
    load_default_keybinds: bool = true,
};

pub const HandleInputFn = fn (engine: *Engine, allocator: std.mem.Allocator) anyerror!void;
pub const UpdateFn = fn (engine: *Engine, allocator: std.mem.Allocator, dt: f32) anyerror!void;
pub const RenderFn = fn (engine: *Engine, allocator: std.mem.Allocator) anyerror!void;

pub const Engine = struct {
    allocator: std.mem.Allocator,
    window: Window,
    physics: PhysicsWorld,
    keybind_manager: keybinds.KeybindManager,
    target_fps: u32,
    handle_input: ?HandleInputFn = null,
    update_game: ?UpdateFn = null,
    render_game: ?RenderFn = null,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, comptime config: EngineConfig) !Self {
        var kb_manager = keybinds.KeybindManager.init(alloc);
        if (config.load_default_keybinds) {
            try kb_manager.loadDefaultBindings();
        }

        return Self{
            .allocator = alloc,
            .window = try Window.init(config.window),
            .physics = try PhysicsWorld.init(alloc, config.physics),
            .keybind_manager = kb_manager,
            .target_fps = config.target_fps,
            .handle_input = null,
            .update_game = null,
            .render_game = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.window.deinit();
        self.physics.deinit();
        self.keybind_manager.deinit();
    }

    // New methods to set the callbacks
    pub fn setHandleInputFn(self: *Self, comptime func: HandleInputFn) void {
        self.handle_input = func;
    }

    pub fn setUpdateFn(self: *Self, comptime func: UpdateFn) void {
        self.update_game = func;
    }

    pub fn setRenderFn(self: *Self, comptime func: RenderFn) void {
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
        const fixed_dt: f32 = if (self.target_fps == 0) (1.0 / 60.0) else (1.0 / @as(f32, @floatFromInt(self.target_fps)));

        while (!rl.windowShouldClose()) {
            if (self.handle_input) |input_fn| {
                try input_fn(self, self.allocator);
            }

            accumulator += rl.getFrameTime();

            while (accumulator >= fixed_dt) {
                // Update physics
                self.physics.update(fixed_dt);

                // Update game logic (if callback is set)
                if (self.update_game) |update_fn| {
                    try update_fn(self, self.allocator, fixed_dt);
                }
                accumulator -= fixed_dt;
            }

            // 3. Render
            rl.beginDrawing();
            rl.clearBackground(rl.Color.white);

            // Render game (if callback is set)
            if (self.render_game) |render_fn| {
                try render_fn(self, self.allocator);
            }

            rl.endDrawing();
        }
    }

    // --- Input Action Wrappers ---
    pub fn isActionPressed(self: *const Self, action: keybinds.GameAction) bool {
        return self.keybind_manager.isActionPressed(action);
    }

    pub fn isActionJustPressed(self: *const Self, action: keybinds.GameAction) bool {
        return self.keybind_manager.isActionJustPressed(action);
    }

    pub fn isActionReleased(self: *const Self, action: keybinds.GameAction) bool {
        return self.keybind_manager.isActionReleased(action);
    }

    pub fn getKeybindManager(self: *Self) *keybinds.KeybindManager {
        return &self.keybind_manager;
    }
    // --- End Input Action Wrappers ---
};
