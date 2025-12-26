const std = @import("std");
const Allocator = std.mem.Allocator;
const options = @import("zixel_options");

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

const Editor = if (options.enable_editor) @import("../editor/Editor.zig") else void;

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

editor: if (options.enable_editor) Editor else void = if (options.enable_editor) undefined else {},

/// Initializes engine systems and the editor overlay.
pub fn init(alloc: Allocator, cfg: Config) !Engine {
    return Engine{
        .alloc = alloc,
        .world = try World.init(alloc, cfg.physics),
        .time = Time.init(cfg.time),
        .input = .{},
        .renderer = .{},
        .scene = null,
        .cfg = cfg,
        .editor = if (options.enable_editor) Editor.init(alloc) else {},
    };
}

/// Frees the scene tree, world, and editor resources.
pub fn deinit(self: *Engine) void {
    if (self.scene) |*s| s.deinit(self.alloc);
    self.scene = null;

    if (options.enable_editor) {
        self.editor.deinit();
    }

    self.world.deinit();
}

/// Configures and starts the Sokol application loop.
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

// --- Scene Management ---

/// Replaces the entire scene tree with a new root.
pub fn setScene(self: *Engine, scene: Scene) void {
    if (self.scene) |*old| old.deinit(self.alloc);
    self.scene = scene;
}

/// Adds a scene as a child of the current root without clearing the tree.
pub fn pushScene(self: *Engine, scene: Scene) !void {
    if (self.scene) |*root| {
        try root.addChild(self.alloc, scene);
    } else {
        self.scene = scene;
    }
}

/// Destroys a specific scene by name anywhere in the tree.
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

/// Allocates and sets a new root scene.
pub fn createScene(self: *Engine, comptime T: type) !void {
    const ptr = try self.alloc.create(T);
    ptr.* = try T.init(self.ctx());
    self.setScene(Scene.init(ptr));
}

/// Allocates and pushes a new scene as a child of the current root.
pub fn pushCreateScene(self: *Engine, comptime T: type) !void {
    const instance = try self.alloc.create(T);
    instance.* = try T.init(self.ctx());
    try self.pushScene(Scene.init(instance));
}

/// Allocates a root scene with custom initialization arguments.
pub fn createSceneWith(self: *Engine, comptime T: type, args: anytype) !void {
    const ptr = try self.alloc.create(T);
    ptr.* = try @call(.auto, T.init, .{self.ctx()} ++ args);
    self.setScene(Scene.init(ptr));
}

/// Searches the tree for a scene by name.
pub fn findScene(self: *Engine, name: []const u8) ?*Scene {
    if (self.scene) |*s| return findRecursive(s, name);
    return null;
}

/// Returns the shared context used to initialize scenes.
pub fn ctx(self: *Engine) Ctx {
    return .{
        .alloc = self.alloc,
        .world = &self.world,
        .renderer = &self.renderer,
        .input = &self.input,
    };
}

// --- Internal Logic ---

/// Recursively looks for a scene by name.
fn findRecursive(current: *Scene, name: []const u8) ?*Scene {
    if (std.mem.eql(u8, current.name, name)) return current;
    for (current.children.items) |*child| {
        if (findRecursive(child, name)) |found| return found;
    }
    return null;
}

/// Walks the tree top-down to process logic and blocking states.
fn updateRecursive(scene: *Scene, dt: f32) bool {
    var i: usize = scene.children.items.len;
    while (i > 0) {
        i -= 1;
        if (updateRecursive(&scene.children.items[i], dt)) return true;
    }
    scene.update(dt);
    return scene.is_blocking;
}

/// Walks the tree bottom-up to draw scenes in the correct order.
fn renderRecursive(scene: *Scene) void {
    scene.render();
    for (scene.children.items) |*child| renderRecursive(child);
}

/// Recovers the Engine pointer from Sokol's userdata.
fn engineFromApp() *Engine {
    return @ptrCast(@alignCast(sapp.userdata().?));
}

// --- Callbacks ---

fn onInit() callconv(.c) void {
    const engine = engineFromApp();
    engine.renderer.init();
    if (options.enable_editor) {
        engine.editor.setup();
        engine.editor.setWorld(&engine.world);
    }
}

fn onFrame() callconv(.c) void {
    const engine = engineFromApp();
    engine.time.beginFrame();

    var ran_fixed_step = false;
    while (engine.time.popFixedStep()) {
        const fdt: f32 = engine.time.cfg.fixed_dt;
        var world_blocked = false;

        if (engine.scene) |*s| world_blocked = updateRecursive(s, fdt);
        if (!world_blocked) engine.world.update(fdt);

        ran_fixed_step = true;
    }

    if (ran_fixed_step) engine.input.endFrame();

    if (options.enable_editor) {
        engine.editor.beginFrame();
        engine.editor.render();
    }

    engine.renderer.beginFrame();
    if (engine.scene) |*s| renderRecursive(s);
    if (options.enable_editor) engine.editor.draw();
    engine.renderer.endFrame();
}

fn onEvent(event: [*c]const sapp.Event) callconv(.c) void {
    const engine = engineFromApp();
    if (options.enable_editor) _ = engine.editor.handleEvent(event);
    engine.input.handleEvent(event);
}

fn onCleanup() callconv(.c) void {
    const engine = engineFromApp();
    engine.deinit();
    engine.renderer.shutdown();
}
