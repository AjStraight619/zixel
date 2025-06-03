const zixel = @import("zixel");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var engine = try zixel.Engine.init(allocator, .{
        .window_width = 1000,
        .window_height = 700,
        .window_title = "Input Example",
        .target_fps = 60,
    });
    defer engine.deinit();

    const ground_shape = zixel.PhysicsShape{ .rectangle = zixel.rl.Rectangle.init(0, 0, 1000, 30) };
    _ = try engine.createStaticBody(zixel.components.Transform{ .position = zixel.rl.Vector2.init(500, 650) }, ground_shape, zixel.rl.Color.dark_gray);

    try engine.run();
}
