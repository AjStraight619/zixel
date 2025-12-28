const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const slog = sokol.log;

const Time = @import("Time.zig");
const Scene = @import("Scene.zig");
const Window = @import("Window.zig");
const Renderer = @import("Renderer.zig");
const Input = @import("Input.zig");
const World = @import("../physics/world.zig");
pub const Ctx = @import("Ctx.zig").Ctx;

pub const Engine = @This();

pub const Config = struct {
    window: Window.Config = .{},
    physics: World.Config = .{},
    time: Time.Config = .{},
    game_dir: ?[]const u8 = null,
};

alloc: std.mem.Allocator,
world: World,
time: Time,
input: Input,
renderer: Renderer,
scene: ?Scene = null,
cfg: Config,

game_dir: ?[]const u8 = null,

/// Initializes engine systems.
pub fn init(alloc: std.mem.Allocator, cfg: Config) !Engine {
    return Engine{
        .alloc = alloc,
        .world = try World.init(alloc, cfg.physics),
        .time = Time.init(cfg.time),
        .input = .{},
        .renderer = .{},
        .scene = null,
        .cfg = cfg,
        .game_dir = cfg.game_dir,
    };
}

/// Frees the scene tree and world resources.
pub fn deinit(self: *Engine) void {
    if (self.scene) |*s| s.deinit(self.alloc);
    self.scene = null;
    self.world.deinit();
}

/// Runs one frame of game logic (Input -> Fixed Update -> Physics).
/// The Editor calls this manually when "Play" is active.
pub fn tick(self: *Engine) void {
    self.time.beginFrame();

    var ran_fixed_step = false;
    while (self.time.popFixedStep()) {
        const fdt: f32 = self.time.cfg.fixed_dt;
        var world_blocked = false;

        if (self.scene) |*s| world_blocked = updateRecursive(s, fdt);
        if (!world_blocked) self.world.update(fdt);

        ran_fixed_step = true;
    }

    if (ran_fixed_step) self.input.endFrame();
}

/// Renders the current scene to the active framebuffer.
/// The Editor calls this to draw the game view.
pub fn render(self: *Engine) void {
    self.renderer.beginFrame();
    if (self.scene) |*s| renderRecursive(s);
    self.renderer.endFrame();
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

pub fn setScene(self: *Engine, scene: Scene) void {
    if (self.scene) |*old| old.deinit(self.alloc);
    self.scene = scene;
}

pub fn pushScene(self: *Engine, scene: Scene) !void {
    if (self.scene) |*root| {
        try root.addChild(self.alloc, scene);
    } else {
        self.scene = scene;
    }
}

pub fn removeScene(self: *Engine, name: []const u8) void {
    if (self.scene) |*root| {
        if (std.mem.eql(u8, root.name, name)) {
            root.deinit(self.alloc);
            self.scene = null;
            return;
        }
        _ = root.removeChild(self.alloc, name);
    }
}

pub fn createScene(self: *Engine, comptime T: type) !void {
    const ptr = try self.alloc.create(T);
    ptr.* = try T.init(self.ctx());
    self.setScene(Scene.init(ptr));
}

pub fn pushCreateScene(self: *Engine, comptime T: type) !void {
    const instance = try self.alloc.create(T);
    instance.* = try T.init(self.ctx());
    try self.pushScene(Scene.init(instance));
}

pub fn createSceneWith(self: *Engine, comptime T: type, args: anytype) !void {
    const ptr = try self.alloc.create(T);
    ptr.* = try @call(.auto, T.init, .{self.ctx()} ++ args);
    self.setScene(Scene.init(ptr));
}

pub fn findScene(self: *Engine, name: []const u8) ?*Scene {
    if (self.scene) |*s| return findRecursive(s, name);
    return null;
}

pub fn ctx(self: *Engine) Ctx {
    return .{
        .alloc = self.alloc,
        .world = &self.world,
        .renderer = &self.renderer,
        .input = &self.input,
    };
}

fn findRecursive(current: *Scene, name: []const u8) ?*Scene {
    if (std.mem.eql(u8, current.name, name)) return current;
    for (current.children.items) |*child| {
        if (findRecursive(child, name)) |found| return found;
    }
    return null;
}

fn updateRecursive(scene: *Scene, dt: f32) bool {
    var i: usize = scene.children.items.len;
    while (i > 0) {
        i -= 1;
        if (updateRecursive(&scene.children.items[i], dt)) return true;
    }
    scene.update(dt);
    return scene.is_blocking;
}

fn renderRecursive(scene: *Scene) void {
    scene.render();
    for (scene.children.items) |*child| renderRecursive(child);
}

fn engineFromApp() *Engine {
    return @ptrCast(@alignCast(sapp.userdata().?));
}

fn onInit() callconv(.c) void {
    const engine = engineFromApp();
    // Engine owns gfx
    engine.renderer.init(true);
}

fn onFrame() callconv(.c) void {
    const engine = engineFromApp();
    engine.tick();
    engine.render();
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
