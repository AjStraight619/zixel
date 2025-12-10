const std = @import("std");
const Allocator = std.mem.Allocator;
const Scene = @import("Scene.zig");
const Window = @import("Window.zig");
const Renderer = @import("Renderer.zig");
const Renderable = @import("Renderable.zig");
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
renderer: Renderer,
renderables: std.ArrayList(Renderable),
cfg: Config,

// File-level global for sokol callbacks to access
var g_engine: ?*Engine = null;

pub fn init(alloc: Allocator, cfg: Config) Engine {
    return .{
        .alloc = alloc,
        .world = World.init(alloc, cfg.physics),
        .renderer = .{},
        .renderables = .empty,
        .cfg = cfg,
    };
}

pub fn deinit(self: *Engine) void {
    // Clean up all renderables
    for (self.renderables.items) |r| {
        r.deinit(self.alloc);
    }
    self.renderables.deinit(self.alloc);
}

/// Add a renderable to the engine. It will be rendered automatically each frame.
pub fn addRenderable(self: *Engine, renderable: Renderable) !void {
    try self.renderables.append(self.alloc, renderable);
}

pub fn run(self: *Engine) void {
    g_engine = self;
    sapp.run(.{
        .init_cb = onInit,
        .frame_cb = onFrame,
        .cleanup_cb = onCleanup,
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

    // Render all renderables
    for (engine.renderables.items) |r| {
        r.render(&engine.world, &engine.renderer);
    }

    engine.renderer.endFrame();
}

fn onCleanup() callconv(.c) void {
    const engine = g_engine orelse return;
    engine.deinit();
    engine.renderer.shutdown();
}
