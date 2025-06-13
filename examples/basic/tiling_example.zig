const std = @import("std");
const zixel = @import("zixel");
const rl = @import("raylib");

// Example: How to use a small tile sprite for a large floor

pub fn drawTiledFloor(texture: rl.Texture, floor_body: *zixel.Body) void {
    const pos = floor_body.getPosition();
    const shape = floor_body.getShape();

    switch (shape) {
        .rectangle => |rect| {
            const floor_width = rect.width;
            const floor_height = rect.height;

            // Tile size (your small sprite)
            const tile_width = @as(f32, @floatFromInt(texture.width));
            const tile_height = @as(f32, @floatFromInt(texture.height));

            // How many tiles we need
            const tiles_x = @ceil(floor_width / tile_width);
            const tiles_y = @ceil(floor_height / tile_height);

            // Draw tiles across the floor
            var y: f32 = 0;
            while (y < tiles_y) : (y += 1) {
                var x: f32 = 0;
                while (x < tiles_x) : (x += 1) {
                    const tile_pos = rl.Vector2{
                        .x = pos.x - floor_width / 2 + x * tile_width,
                        .y = pos.y - floor_height / 2 + y * tile_height,
                    };

                    rl.drawTextureV(texture, tile_pos, rl.Color.white);
                }
            }
        },
        else => {
            // Not a rectangle, just draw normally
            rl.drawTextureV(texture, pos, rl.Color.white);
        },
    }
}

// Alternative: Use raylib's built-in tiling
pub fn drawTiledFloorSimple(texture: rl.Texture, floor_body: *zixel.Body) void {
    const pos = floor_body.getPosition();
    const shape = floor_body.getShape();

    switch (shape) {
        .rectangle => |rect| {
            // Source: your small tile
            const source = rl.Rectangle{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(texture.width),
                .height = @floatFromInt(texture.height),
            };

            // Destination: the entire floor area
            const dest = rl.Rectangle{
                .x = pos.x - rect.width / 2,
                .y = pos.y - rect.height / 2,
                .width = rect.width,
                .height = rect.height,
            };

            // This will stretch the tile - not what we want usually
            rl.drawTexturePro(texture, source, dest, rl.Vector2.zero(), 0, rl.Color.white);
        },
        else => {},
    }
}
