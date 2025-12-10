const std = @import("std");
const World = @import("../physics/world.zig");
const Renderer = @import("Renderer.zig");
const Color = Renderer.Color;
const Allocator = std.mem.Allocator;

/// Built-in sprite type for rendering colored rectangles.
/// Users can use this directly without writing custom render code.
pub const Sprite = @This();

x: f32,
y: f32,
width: f32,
height: f32,
color: Color,

/// Create a new sprite with the given properties.
pub fn create(alloc: Allocator, x: f32, y: f32, width: f32, height: f32, color: Color) !*Sprite {
    const sprite = try alloc.create(Sprite);
    sprite.* = .{
        .x = x,
        .y = y,
        .width = width,
        .height = height,
        .color = color,
    };
    return sprite;
}

/// Render the sprite. Called automatically by the engine.
pub fn render(self: *Sprite, world: *World, renderer: *Renderer) void {
    _ = world;
    renderer.drawRect(self.x, self.y, self.width, self.height, self.color);
}

/// Clean up the sprite. Called automatically by the engine.
pub fn deinit(self: *Sprite, alloc: Allocator) void {
    alloc.destroy(self);
}
