const std = @import("std");
const sokol = @import("sokol");
const sglue = sokol.glue;
const simgui = sokol.imgui;
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;

const Editor = @import("Editor.zig");
const Project = @import("project.zig").Project;

const Toolbar = @import("panels/toolbar/Toolbar.zig");
const Hierarchy = @import("panels/Hierarchy.zig");
const Inspector = @import("panels/Inspector.zig");
const Console = @import("panels/Console.zig");

const EditorApp = struct {
    engine: zixel.Engine,
    editor: Editor,
    is_playing: bool = false,
};

var app: EditorApp = undefined;

fn onInit() callconv(.c) void {
    sokol.gfx.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    simgui.setup(.{ .logger = .{ .func = sokol.log.func } });

    app.editor = Editor.init(std.heap.c_allocator);

    var game_dir: []const u8 = ".";

    if (std.process.argsAlloc(std.heap.c_allocator)) |args| {
        if (args.len > 1) {
            game_dir = args[1];
        }
    } else |err| {
        std.debug.print("Warning: Could not parse arguments: {}\n", .{err});
    }

    Project.scaffold(std.heap.c_allocator, game_dir) catch |err| {
        std.debug.panic("Failed to scaffold project directory '{s}': {}\n", .{ game_dir, err });
    };

    app.engine = zixel.Engine.init(std.heap.c_allocator, .{
        .window = .{ .title = "Viewport", .width = 800, .height = 600 },
        .physics = .{ .debug_logging = true },
        .game_dir = game_dir,
    }) catch |err| {
        std.debug.panic("Failed to initialize Engine: {}\n", .{err});
    };

    app.engine.renderer.init(false);
    app.engine.renderer._owns_pass = false;

    app.editor.world = &app.engine.world;
    app.editor.log("Editor Initialized");
}

fn onFrame() callconv(.c) void {
    const dt = sokol.app.frameDuration();

    simgui.newFrame(.{
        .width = sokol.app.width(),
        .height = sokol.app.height(),
        .delta_time = dt,
        .dpi_scale = sokol.app.dpiScale(),
    });

    if (app.is_playing) {
        app.engine.tick();
    }

    var pass_action = sokol.gfx.PassAction{};
    pass_action.colors[0] = .{ .load_action = .CLEAR, .clear_value = .{ .r = 0.1, .g = 0.1, .b = 0.1, .a = 1 } };

    sokol.gfx.beginPass(.{ .action = pass_action, .swapchain = sglue.swapchain() });

    app.engine.render();

    Toolbar.draw(&app.editor, &app.is_playing);
    Hierarchy.draw(&app.editor);
    Inspector.draw(&app.editor);
    Console.draw(&app.editor);

    simgui.render();

    sokol.gfx.endPass();
    sokol.gfx.commit();
}

fn onEvent(e: [*c]const sokol.app.Event) callconv(.c) void {
    if (simgui.handleEvent(e.*)) return;
    app.engine.input.handleEvent(e);
}

fn onCleanup() callconv(.c) void {
    app.engine.deinit();
    app.editor.deinit();
    simgui.shutdown();
    sokol.gfx.shutdown();
}

pub fn main() void {
    sokol.app.run(.{
        .init_cb = onInit,
        .frame_cb = onFrame,
        .event_cb = onEvent,
        .cleanup_cb = onCleanup,
        .window_title = "Zixel Editor",
        .width = 1280,
        .height = 720,
        .logger = .{ .func = sokol.log.func },
    });
}
