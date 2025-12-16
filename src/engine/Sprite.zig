const std = @import("std");
const World = @import("../physics/world.zig");
const BodyHandle = World.BodyHandle;
const Renderer = @import("Renderer.zig");
const Color = Renderer.Color;
const Vec2 = @import("../math/vec2.zig");
const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;

/// A sprite that can optionally be linked to a physics body.
/// If linked, position and size come from the body.
/// If not linked, uses its own position and size.
pub const Sprite = @This();

// Physics linkage (optional)
handle: ?BodyHandle = null,

// Used when no body is attached (or as offset from body)
position: Vec2 = Vec2.zero,
width: f32 = 0,
height: f32 = 0,

color: Color,

/// Create a sprite linked to a physics body (dimensions come from shape)
pub fn fromBody(handle: BodyHandle, color: Color) Sprite {
    return .{
        .handle = handle,
        .color = color,
    };
}

/// Create a standalone sprite (no physics)
pub fn fromRect(x: f32, y: f32, w: f32, h: f32, color: Color) Sprite {
    return .{
        .position = Vec2.init(x, y),
        .width = w,
        .height = h,
        .color = color,
    };
}

/// Render the sprite
pub fn render(self: *const Sprite, world: *const World, renderer: *Renderer) void {
    if (self.handle) |h| {
        // Linked to physics body - render based on shape type
        if (world.getBodyConst(h)) |body| {
            switch (body.shape) {
                .circle => |c| {
                    // Circle: position is center
                    renderer.drawCircle(body.position.x, body.position.y, c.radius, self.color);
                },
                .rectangle => |r| {
                    // Rectangle: use rotated rect (handles rotation=0 fine too)
                    renderer.drawRotatedRect(body.position.x, body.position.y, r.width, r.height, body.rotation, self.color);
                },
            }
        }
    } else {
        // Standalone sprite - use own position/size (position is top-left)
        renderer.drawRect(self.position.x, self.position.y, self.width, self.height, self.color);
    }
}
