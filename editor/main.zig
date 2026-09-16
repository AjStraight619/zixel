const std = @import("std");
const sokol = @import("sokol");
const sglue = sokol.glue;
const simgui = sokol.imgui;
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;

const Editor = @import("Editor.zig");
const toolbar = @import("toolbar/toolbar.zig");
const project = @import("project.zig");

const hierarchy = @import("panels/hierarchy.zig");
const inspector = @import("panels/inspector.zig");
const console = @import("panels/console.zig");

const Zixel = struct {
    engine: zixel.Engine,
    editor: Editor,
    is_playing: bool = false,
};

var app: Zixel = undefined;

fn onInit() callconv(.c) void {
    sokol.gfx.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    simgui.setup(.{ .logger = .{ .func = sokol.log.func } });

    var raw_path: []const u8 = ".";
    if (std.process.argsAlloc(std.heap.c_allocator)) |args| {
        if (args.len > 1) {
            raw_path = args[1];
        }
    } else |err| {
        std.debug.print("Warning: Could not parse arguments: {}\n", .{err});
    }

    // We try to create the project structure. If the folder doesn't exist, this makes it.
    project.scaffold(std.heap.c_allocator, raw_path) catch |err| {
        std.debug.panic("Failed to scaffold project at '{s}': {}\n", .{ raw_path, err });
    };

    // Now that we know the folder exists, we get the real absolute path.
    const abs_game_path = std.fs.cwd().realpathAlloc(std.heap.c_allocator, raw_path) catch |err| {
        std.debug.panic("Could not resolve absolute path for '{s}': {}\n", .{ raw_path, err });
    };

    // Pass the absolute path. The editor will duplicate it.
    app.editor = Editor.init(std.heap.c_allocator, abs_game_path) catch |err| {
        std.debug.panic("Failed to init Editor: {}\n", .{err});
    };

    app.engine = zixel.Engine.init(std.heap.c_allocator, .{
        .window = .{ .title = "Viewport", .width = 800, .height = 600 },
        .physics = .{ .debug_logging = true },
        .game_dir = abs_game_path, // Engine uses the absolute path too
    }) catch |err| {
        std.debug.panic("Failed to initialize Engine: {}\n", .{err});
    };

    app.engine.renderer.init(false);
    app.engine.renderer._owns_pass = false;

    // Link the editor to the engine's world
    app.editor.world = &app.engine.world;

    if (std.fmt.allocPrint(std.heap.c_allocator, "Editor Initialized. Project: {s}", .{abs_game_path})) |msg| {
        app.editor.log(msg);
    } else |_| {
        app.editor.log("Editor Initialized");
    }
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

    toolbar.draw(&app.editor, &app.is_playing);

    hierarchy.draw(&app.editor);
    inspector.draw(&app.editor);
    console.draw(&app.editor);

    app.editor.drawOverlays();

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
