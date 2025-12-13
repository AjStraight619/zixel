const std = @import("std");
const Allocator = std.mem.Allocator;
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
    physics: World.PhysicsConfig = .{},
};

alloc: Allocator,
world: World,
input: Input,
renderer: Renderer,
scene: ?Scene = null,
cfg: Config,

// File-level global for sokol callbacks to access
var g_engine: ?*Engine = null;

pub fn init(alloc: Allocator, cfg: Config) !Engine {
    return .{
        .alloc = alloc,
        .world = try World.init(alloc, cfg.physics),
        .input = .{},
        .renderer = .{},
        .scene = null,
        .cfg = cfg,
    };
}

pub fn setScene(self: *Engine, scene: Scene) void {
    if (self.scene) |old| {
        old.deinit(self.alloc);
    }
    self.scene = scene;
}

pub fn deinit(self: *Engine) void {
    if (self.scene) |s| {
        s.deinit(self.alloc);
    }
    self.scene = null;

    // adjust this to match your World API:
    self.world.deinit(); // or self.world.deinit(self.alloc);
}

pub fn run(self: *Engine) void {
    g_engine = self;
    sapp.run(.{
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

fn onInit() callconv(.c) void {
    const engine = g_engine orelse return;
    engine.renderer.init();
}

fn onFrame() callconv(.c) void {
    const engine = g_engine orelse return;
    const dt: f32 = @floatCast(sapp.frameDuration());

    // Update physics
    engine.world.update(dt);

    engine.renderer.beginFrame();

    if (engine.scene) |s| {
        s.update(dt);
        s.render();
    }

    engine.renderer.endFrame();

    // Clear per-frame input state (pressed/released)
    engine.input.endFrame();
}

fn onEvent(event: [*c]const sapp.Event) callconv(.c) void {
    const engine = g_engine orelse return;
    engine.input.handleEvent(event);
}

fn onCleanup() callconv(.c) void {
    const engine = g_engine orelse return;
    engine.deinit();
    engine.renderer.shutdown();
}
