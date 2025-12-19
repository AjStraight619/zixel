const std = @import("std");
const Allocator = std.mem.Allocator;

const Time = @import("Time.zig");
const Scene = @import("Scene.zig");
const Window = @import("Window.zig");
const Renderer = @import("Renderer.zig");
const Input = @import("Input.zig");
const World = @import("../physics/world.zig");
pub const Ctx = @import("Ctx.zig").Ctx;

const sokol = @import("sokol");
const sapp = sokol.app;
const slog = sokol.log;

const Engine = @This();

pub const Config = struct {
    window: Window.Config = .{},
    physics: World.Config = .{},
    time: Time.Config = .{},
};

alloc: Allocator,
world: World,
time: Time,
input: Input,
renderer: Renderer,
scene: ?Scene = null,
cfg: Config,

pub fn init(alloc: Allocator, cfg: Config) !Engine {
    return .{
        .alloc = alloc,
        .world = try World.init(alloc, cfg.physics),
        .time = Time.init(cfg.time),
        .input = .{},
        .renderer = .{},
        .scene = null,
        .cfg = cfg,
    };
}

pub fn setScene(self: *Engine, scene: Scene) void {
    if (self.scene) |old| old.deinit(self.alloc);
    self.scene = scene;
}

/// Get context for creating scenes
pub fn ctx(self: *Engine) Ctx {
    return .{
        .alloc = self.alloc,
        .world = &self.world,
        .renderer = &self.renderer,
        .input = &self.input,
    };
}

/// Create and set a scene from any type that implements the Scene interface.
/// The scene type must have: `pub fn init(ctx: Ctx) !T` (or `!*T`)
/// This allocates the scene and wires it up automatically.
pub fn createScene(self: *Engine, comptime T: type) !void {
    const ptr = try self.alloc.create(T);
    ptr.* = try T.init(self.ctx());
    self.setScene(Scene.init(ptr));
}

/// Create and set a scene, passing extra arguments to init.
/// Scene type must have: `pub fn init(ctx: Ctx, args: ExtraArgs) !T`
pub fn createSceneWith(self: *Engine, comptime T: type, args: anytype) !void {
    const ptr = try self.alloc.create(T);
    ptr.* = try @call(.auto, T.init, .{self.ctx()} ++ args);
    self.setScene(Scene.init(ptr));
}

pub fn deinit(self: *Engine) void {
    if (self.scene) |s| s.deinit(self.alloc);
    self.scene = null;

    self.world.deinit();
}

pub fn run(self: *Engine) void {
    sapp.run(.{
        .user_data = self,
        .init_cb = onInit,
        .frame_cb = onFrame,
        .cleanup_cb = onCleanup,
        .event_cb = onEvent,

        .width = self.cfg.window.width,
        .height = self.cfg.window.height,
        .window_title = self.cfg.window.title,
        .fullscreen = self.cfg.window.fullscreen,
        .high_dpi = self.cfg.window.high_dpi,
        .sample_count = self.cfg.window.sample_count,
        .swap_interval = self.cfg.window.swap_interval,

        .logger = .{ .func = slog.func },
    });
}

fn engineFromApp() *Engine {
    const ud = sapp.userdata().?;
    return @ptrCast(@alignCast(ud));
}

// --- callbacks ---
fn onInit() callconv(.c) void {
    const engine = engineFromApp();
    engine.renderer.init();
}

fn onFrame() callconv(.c) void {
    const engine = engineFromApp();

    // Drive time first (clamp, pause, fixed-step accumulator, fps, etc.)
    engine.time.beginFrame();

    // Fixed-step sim loop:
    // - physics runs on fixed dt for stability/determinism
    while (engine.time.popFixedStep()) {
        const fdt: f32 = engine.time.cfg.fixed_dt;

        engine.world.update(fdt);

        if (engine.scene) |s| {
            s.update(fdt);
        }
    }

    // Render once per frame (optionally interpolate using engine.time.alpha())
    engine.renderer.beginFrame();

    if (engine.scene) |s| {
        s.render();
    }

    engine.renderer.endFrame();

    engine.input.endFrame();
}

fn onEvent(event: [*c]const sapp.Event) callconv(.c) void {
    const engine = engineFromApp();
    engine.input.handleEvent(event);
}

fn onCleanup() callconv(.c) void {
    const engine = engineFromApp();
    engine.deinit();
    engine.renderer.shutdown();
}
