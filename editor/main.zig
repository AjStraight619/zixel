const std = @import("std");
const Allocator = std.mem.Allocator;
const zixel = @import("zixel_new");

const sokol = @import("sokol");
const sapp = sokol.app;
const sg = sokol.gfx;
const sgl = sokol.gl;
const sglue = sokol.glue;
const simgui = sokol.imgui;
const slog = sokol.log;

const Editor = @import("Editor.zig");

var state: struct {
    alloc: Allocator,
    editor: Editor,
    pass_action: sg.PassAction,
} = undefined;

pub fn main() void {
    state.alloc = std.heap.page_allocator;
    state.editor = Editor.init(state.alloc);

    sapp.run(.{
        .init_cb = onInit,
        .frame_cb = onFrame,
        .cleanup_cb = onCleanup,
        .event_cb = onEvent,

        .width = 1600,
        .height = 900,
        .window_title = "Zixel Editor",
        .high_dpi = true,
        .icon = .{ .sokol_default = true },

        .logger = .{ .func = slog.func },
    });
}

fn onInit() callconv(.c) void {
    // Initialize sokol-gfx
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    // Initialize sokol-gl (for game rendering)
    sgl.setup(.{
        .logger = .{ .func = slog.func },
    });

    // Initialize Dear ImGui
    simgui.setup(.{
        .logger = .{ .func = slog.func },
    });

    // Dark background
    state.pass_action = .{
        .colors = .{
            .{
                .load_action = .CLEAR,
                .clear_value = .{ .r = 0.08, .g = 0.08, .b = 0.10, .a = 1.0 },
            },
            .{},
            .{},
            .{},
            .{},
            .{},
            .{},
            .{},
        },
    };
}

fn onFrame() callconv(.c) void {
    // Begin ImGui frame
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });

    // Render editor UI
    state.editor.render();

    // Render
    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });

    // Draw game scene (sokol-gl) first
    sgl.draw();

    // Draw ImGui on top
    simgui.render();

    sg.endPass();
    sg.commit();
}

fn onEvent(ev: [*c]const sapp.Event) callconv(.c) void {
    // Forward events to ImGui (dereference the pointer)
    _ = simgui.handleEvent(ev.*);
}

fn onCleanup() callconv(.c) void {
    state.editor.deinit();
    simgui.shutdown();
    sgl.shutdown();
    sg.shutdown();
}
