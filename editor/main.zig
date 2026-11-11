const std = @import("std");
const sokol = @import("sokol");
const sglue = sokol.glue;
const simgui = sokol.imgui;
const zixel = @import("zixel_new");
const logging = @import("logging.zig");
const Args = @import("Args.zig");
const log = std.log.scoped(.zixel_editor);

pub const std_options: std.Options = .{
    // Keep debug callsites available for --debug-log; the sink filters at runtime.
    .log_level = .debug,
    .logFn = logging.logFn,
};
pub const panic = std.debug.FullPanic(logging.panic);

const Editor = @import("Editor.zig");
const toolbar = @import("toolbar.zig");
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
var project_path: []const u8 = undefined;

fn onInit() callconv(.c) void {
    sokol.gfx.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = zixel.logging.sokolLog },
    });
    simgui.setup(.{ .logger = .{ .func = zixel.logging.sokolLog } });

    const abs_game_path = project_path;

    // Pass the absolute path. The editor will duplicate it.
    app.editor = Editor.init(std.heap.c_allocator, abs_game_path) catch |err| {
        std.debug.panic("Failed to init Editor: {}\n", .{err});
    };

    app.engine = zixel.Engine.init(std.heap.c_allocator, .{
        .window = .{ .title = "Viewport", .width = 800, .height = 600 },
        .game_dir = abs_game_path, // Engine uses the absolute path too
    }) catch |err| {
        std.debug.panic("Failed to initialize Engine: {}\n", .{err});
    };

    app.engine.renderer.init(false);
    app.engine.renderer.owns_pass = false;

    // Link the editor to the engine's world
    app.editor.world = &app.engine.world;

    log.info("Opened project: {s}", .{abs_game_path});
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
    sokol.gl.shutdown();
    sokol.gfx.shutdown();
    log.info("Editor stopped", .{});
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(alloc);
    var args = Args.parse(alloc, argv[1..]) catch |err| {
        log.err("Invalid arguments: {s}\n{s}", .{ @errorName(err), Args.usage });
        return err;
    };
    defer args.deinit(alloc);
    if (args.help) {
        try std.Io.File.stdout().writeStreamingAll(init.io, Args.usage);
        return;
    }
    var logger = zixel.logging.Logger.init(alloc, init.io, .{
        .file_path = args.log_file,
        .debug_scopes = args.debug_scopes.items,
    }) catch |err| {
        log.err("Could not initialize logging (file={s}): {s}", .{ args.log_file orelse "disabled", @errorName(err) });
        return err;
    };
    defer logger.deinit();
    logging.active = &logger;
    defer logging.active = null;
    log.info("Starting Zixel {s}; log file: {s}", .{ @import("zixel_buildinfo").version, args.log_file orelse "disabled" });
    const raw_path = args.project_path;
    project.scaffold(alloc, init.io, raw_path) catch |err| {
        log.err("Could not initialize project '{s}': {s}", .{ raw_path, @errorName(err) });
        return err;
    };
    project_path = try std.Io.Dir.cwd().realPathFileAlloc(init.io, raw_path, alloc);
    sokol.app.run(.{
        .init_cb = onInit,
        .frame_cb = onFrame,
        .event_cb = onEvent,
        .cleanup_cb = onCleanup,
        .window_title = "Zixel Editor",
        .width = 1280,
        .height = 720,
        .logger = .{ .func = zixel.logging.sokolLog },
    });
}
