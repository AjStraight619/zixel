const World = @import("World.zig");
const Renderer = @import("Renderer.zig");

/// Render all entities that have sprites
pub fn draw(renderer: *Renderer, world: *const World) void {
    for (world.slots.items) |*slot| {
        if (!slot.alive) continue;
        if (slot.entity.sprite) |sprite| {
            const body = &slot.entity.body;
            switch (body.shape) {
                .circle => |c| {
                    renderer.drawCircle(body.position.x, body.position.y, c.radius, sprite.color);
                },
                .rectangle => |r| {
                    renderer.drawRotatedRect(body.position.x, body.position.y, r.width, r.height, body.rotation, sprite.color);
                },
            }
        }
    }
}
