const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;
const sglue = sokol.glue;
const slog = sokol.log;
const sapp = sokol.app;

const Renderer = @This();

pub const Color = @import("Color.zig");

clear_color: Color = .{ .r = 0.1, .g = 0.1, .b = 0.15, .a = 1 },

/// DO NOT MODIFY THIS VARIABLE
_owns_pass: bool = true,

pub fn init(self: *Renderer, setup_gfx: bool) void {
    _ = self;

    if (setup_gfx) {
        sg.setup(.{
            .environment = sglue.environment(),
            .logger = .{ .func = slog.func },
        });
    }
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

    self.setupMatrices();

    if (self._owns_pass) {
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
}

fn setupMatrices(_: *Renderer) void {
    sgl.defaults();
    sgl.matrixModeProjection();
    sgl.loadIdentity();
    sgl.ortho(0, sapp.widthf(), sapp.heightf(), 0, -1, 1);
    sgl.matrixModeModelview();
    sgl.loadIdentity();
}

pub fn endFrame(self: *Renderer) void {
    sgl.draw();
    if (self._owns_pass) {
        sg.endPass();
        sg.commit();
    }
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

/// Draw a rotated rectangle (cx, cy = center, rotation in radians)
pub fn drawRotatedRect(self: *Renderer, cx: f32, cy: f32, w: f32, h: f32, rotation: f32, color: Color) void {
    _ = self;
    const hw = w / 2.0;
    const hh = h / 2.0;
    const cos_r = @cos(rotation);
    const sin_r = @sin(rotation);

    // Compute rotated corners relative to center
    const corners = [4][2]f32{
        .{ -hw, -hh }, // top-left
        .{ hw, -hh }, // top-right
        .{ hw, hh }, // bottom-right
        .{ -hw, hh }, // bottom-left
    };

    sgl.beginQuads();
    sgl.c4f(color.r, color.g, color.b, color.a);
    for (corners) |corner| {
        const rx = corner[0] * cos_r - corner[1] * sin_r + cx;
        const ry = corner[0] * sin_r + corner[1] * cos_r + cy;
        sgl.v2f(rx, ry);
    }
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

/// Draw a filled circle using triangles
pub fn drawCircle(self: *Renderer, cx: f32, cy: f32, radius: f32, color: Color) void {
    _ = self;
    const segments: u32 = 24;
    const pi = std.math.pi;
    const angle_step = 2.0 * pi / @as(f32, @floatFromInt(segments));

    sgl.beginTriangles();
    sgl.c4f(color.r, color.g, color.b, color.a);

    // Draw triangle fan manually: center + two edge points per triangle
    for (0..segments) |i| {
        const angle1 = @as(f32, @floatFromInt(i)) * angle_step;
        const angle2 = @as(f32, @floatFromInt(i + 1)) * angle_step;

        // Center
        sgl.v2f(cx, cy);
        // Edge point 1
        sgl.v2f(cx + radius * @cos(angle1), cy + radius * @sin(angle1));
        // Edge point 2
        sgl.v2f(cx + radius * @cos(angle2), cy + radius * @sin(angle2));
    }

    sgl.end();
}

pub fn beginEmbedded(self: *Renderer) void {
    self.setupMatrices();
}

pub fn endEmbedded(_: *Renderer) void {
    sgl.draw();
}
