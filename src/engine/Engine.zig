const std = @import("std");
const Allocator = std.mem.Allocator;

const Time = @import("../core/Time.zig");
const Scene = @import("Scene.zig");
const Window = @import("Window.zig");
const Renderer = @import("Renderer.zig");
const Input = @import("Input.zig");
const World = @import("../physics/world.zig");

const sokol = @import("sokol");
const sapp = sokol.app;
const slog = sokol.log;

pub const Engine = @This();

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

// --- user_data plumbing ---
// NOTE: sokol-zig has used different names across versions.
// Try `sapp.userdata()` first. If your build says it doesn't exist,
// change it to `sapp.userData()` (or whatever your binding exposes).
fn engineFromApp() *Engine {
    const ud = sapp.userdata().?; // <-- if this name fails, rename it (see note above)
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
    // - scene update can also run on fixed dt (your choice)
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
