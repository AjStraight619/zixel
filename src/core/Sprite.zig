const std = @import("std");
const World = @import("../physics/world.zig");
const BodyHandle = World.BodyHandle;
const Renderer = @import("Renderer.zig");
const Color = Renderer.Color;

/// A sprite that renders based on a physics body's position.
/// Dimensions are derived from the body's shape - no duplication.
pub const Sprite = @This();

handle: BodyHandle,
color: Color,

/// Create a sprite linked to a physics body
pub fn init(handle: BodyHandle, color: Color) Sprite {
    return .{
        .handle = handle,
        .color = color,
    };
}

/// Render the sprite using the body's position and shape dimensions
pub fn render(self: *const Sprite, world: *const World, renderer: *Renderer) void {
    if (world.getBodyConst(self.handle)) |body| {
        const s = body.shape.size();
        const draw_x = body.position.x - s.width / 2;
        const draw_y = body.position.y - s.height / 2;
        renderer.drawRect(draw_x, draw_y, s.width, s.height, self.color);
    }
}
