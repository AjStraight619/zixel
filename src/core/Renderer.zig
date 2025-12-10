const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;
const sglue = sokol.glue;
const slog = sokol.log;
const sapp = sokol.app;

pub const Renderer = @This();

pub const Color = struct {
    r: f32 = 1,
    g: f32 = 1,
    b: f32 = 1,
    a: f32 = 1,

    pub const white = Color{};
    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const red = Color{ .r = 1, .g = 0, .b = 0 };
    pub const green = Color{ .r = 0, .g = 1, .b = 0 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 1 };
    pub const yellow = Color{ .r = 1, .g = 1, .b = 0 };
    pub const cyan = Color{ .r = 0, .g = 1, .b = 1 };
    pub const magenta = Color{ .r = 1, .g = 0, .b = 1 };
};

clear_color: Color = .{ .r = 0.1, .g = 0.1, .b = 0.15, .a = 1 },

pub fn init(self: *Renderer) void {
    _ = self;
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    sgl.setup(.{
        .logger = .{ .func = slog.func },
    });
}

pub fn shutdown(self: *Renderer) void {
    _ = self;
    sgl.shutdown();
    sg.shutdown();
}

pub fn beginFrame(self: *Renderer) void {
    // Set up 2D orthographic projection (0,0 at top-left)
    sgl.defaults();
    sgl.matrixModeProjection();
    sgl.loadIdentity();
    sgl.ortho(0, sapp.widthf(), sapp.heightf(), 0, -1, 1);
    sgl.matrixModeModelview();
    sgl.loadIdentity();

    sg.beginPass(.{
        .action = .{
            .colors = .{
                .{
                    .load_action = .CLEAR,
                    .clear_value = .{
                        .r = self.clear_color.r,
                        .g = self.clear_color.g,
                        .b = self.clear_color.b,
                        .a = self.clear_color.a,
                    },
                },
                .{},
                .{},
                .{},
                .{},
                .{},
                .{},
                .{},
            },
        },
        .swapchain = sglue.swapchain(),
    });
}

pub fn endFrame(_: *Renderer) void {
    sgl.draw();
    sg.endPass();
    sg.commit();
}

pub fn drawRect(self: *Renderer, x: f32, y: f32, w: f32, h: f32, color: Color) void {
    _ = self;
    sgl.beginQuads();
    sgl.c4f(color.r, color.g, color.b, color.a);
    sgl.v2f(x, y);
    sgl.v2f(x + w, y);
    sgl.v2f(x + w, y + h);
    sgl.v2f(x, y + h);
    sgl.end();
}

pub fn drawRectOutline(self: *Renderer, x: f32, y: f32, w: f32, h: f32, color: Color) void {
    _ = self;
    sgl.beginLineStrip();
    sgl.c4f(color.r, color.g, color.b, color.a);
    sgl.v2f(x, y);
    sgl.v2f(x + w, y);
    sgl.v2f(x + w, y + h);
    sgl.v2f(x, y + h);
    sgl.v2f(x, y);
    sgl.end();
}

pub fn drawLine(self: *Renderer, x1: f32, y1: f32, x2: f32, y2: f32, color: Color) void {
    _ = self;
    sgl.beginLines();
    sgl.c4f(color.r, color.g, color.b, color.a);
    sgl.v2f(x1, y1);
    sgl.v2f(x2, y2);
    sgl.end();
}

pub fn drawTriangle(self: *Renderer, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, color: Color) void {
    _ = self;
    sgl.beginTriangles();
    sgl.c4f(color.r, color.g, color.b, color.a);
    sgl.v2f(x1, y1);
    sgl.v2f(x2, y2);
    sgl.v2f(x3, y3);
    sgl.end();
}
