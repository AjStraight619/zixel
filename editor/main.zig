const std = @import("std");
const sokol = @import("sokol");
const sglue = sokol.glue;
const simgui = sokol.imgui;
const zixel = @import("zixel_new");

const Editor = @import("Editor.zig");

// Import Panels
const Toolbar = @import("panels/Toolbar.zig");
const Hierarchy = @import("panels/Hierarchy.zig");
const Inspector = @import("panels/Inspector.zig");
const Console = @import("panels/Console.zig");

// Global Application Container
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

    app.engine = zixel.Engine.init(std.heap.c_allocator, .{
        .window = .{ .title = "Viewport", .width = 800, .height = 600 },
        .physics = .{ .debug_logging = true },
    }) catch unreachable;

    // Editor owns gfx
    app.engine.renderer.init(false);

    //  Tells the Engine "Don't clear the screen/start a pass, I'm doing it."
    app.engine.renderer._owns_pass = false;

    app.editor.world = &app.engine.world;
    app.editor.log("Editor Initialized");
}

fn onFrame() callconv(.c) void {
    const dt = sokol.app.frameDuration();

    // 1. Begin UI Frame
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
    // Clear background to dark gray
    pass_action.colors[0] = .{ .load_action = .CLEAR, .clear_value = .{ .r = 0.1, .g = 0.1, .b = 0.1, .a = 1 } };

    // Editor starts the Main Pass
    sokol.gfx.beginPass(.{ .action = pass_action, .swapchain = sglue.swapchain() });

    // Since _owns_pass = false, this effectively just draws the sprites without clearing
    app.engine.render();

    Toolbar.draw(&app.editor, &app.is_playing);
    Hierarchy.draw(&app.editor);
    Inspector.draw(&app.editor);
    Console.draw(&app.editor);

    simgui.render();

    // Editor ends the Main Pass
    sokol.gfx.endPass();
    sokol.gfx.commit();
}

fn onEvent(e: [*c]const sokol.app.Event) callconv(.c) void {
    // UI gets priority
    if (simgui.handleEvent(e.*)) return;

    // Engine gets seconds
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
