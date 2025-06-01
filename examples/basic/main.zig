const std = @import("std");
const zixel = @import("zixel");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the ECS engine
    var engine = try zixel.Engine.init(allocator, .{
        .window_width = 800,
        .window_height = 600,
        .window_title = "Zixel Basic Example",
        .target_fps = 60,
    });
    defer engine.deinit();

    // Create a player
    _ = try engine.createPlayer(zixel.Vector2.init(100, 100));

    // Create some platforms
    _ = try engine.createPlatform(zixel.Vector2.init(400, 500), zixel.Vector2.init(200, 50));
    _ = try engine.createPlatform(zixel.Vector2.init(200, 350), zixel.Vector2.init(150, 30));

    // Create a camera
    _ = try engine.createCamera(zixel.Vector2.init(400, 300));

    // Create some UI text
    _ = try engine.createText(zixel.Vector2.init(10, 10), "Basic Zixel ECS Demo", 20);
    _ = try engine.createText(zixel.Vector2.init(10, 35), "WASD: Move, Space: Jump", 16);

    // Run the game
    try engine.run();
}
