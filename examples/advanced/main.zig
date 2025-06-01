const std = @import("std");
const rl = @import("raylib");
const zixel = @import("zixel");
const PhysicsShape = @import("../../src/core/math/shapes.zig").PhysicsShape;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try zixel.ECSEngine.init(allocator, .{
        .window_width = 1200,
        .window_height = 800,
        .window_title = "Advanced ECS Demo with Physics",
        .target_fps = 60,
        .enable_gui = true,
    });
    defer engine.deinit();

    try setupScene(&engine);

    // Run the engine's main loop (without custom gameLoop callback)
    try engine.run();
}

fn setupScene(engine: *zixel.ECSEngine) !void {
    std.debug.print("Setting up advanced physics scene...\n", .{});

    // Create main camera FIRST - this is crucial for rendering
    const camera_entity = engine.createEntity();
    try engine.addComponent(camera_entity, zixel.components.Transform{
        .position = rl.Vector2.init(600, 400), // Center of screen
    });
    try engine.addComponent(camera_entity, zixel.components.Camera2D{
        .target = rl.Vector2.init(600, 400),
        .offset = rl.Vector2.init(600, 400), // Screen center
        .zoom = 1.0,
        .rotation = 0.0,
        .is_main = true,
    });
    std.debug.print("Created camera entity: {d}\n", .{camera_entity});

    // Create platforms using physics system
    std.debug.print("Creating platforms...\n", .{});
    const platform1 = try engine.createPlatform(rl.Vector2.init(200, 700), rl.Vector2.init(200, 20));
    const platform2 = try engine.createPlatform(rl.Vector2.init(600, 600), rl.Vector2.init(200, 20));
    const platform3 = try engine.createPlatform(rl.Vector2.init(1000, 500), rl.Vector2.init(200, 20));
    std.debug.print("Created platforms: {d}, {d}, {d}\n", .{ platform1, platform2, platform3 });

    // Create some dynamic physics objects
    std.debug.print("Creating dynamic objects...\n", .{});
    const circle_shape = PhysicsShape{ .circle = .{ .radius = 25 } };
    const circle1 = try engine.createDynamicObject(rl.Vector2.init(100, 100), circle_shape);
    const circle2 = try engine.createDynamicObject(rl.Vector2.init(200, 100), circle_shape);
    std.debug.print("Created circles: {d}, {d}\n", .{ circle1, circle2 });

    const box_shape = PhysicsShape{ .rectangle = rl.Rectangle{ .x = 0, .y = 0, .width = 40, .height = 40 } };
    const box1 = try engine.createDynamicObject(rl.Vector2.init(300, 100), box_shape);
    const box2 = try engine.createDynamicObject(rl.Vector2.init(400, 100), box_shape);
    std.debug.print("Created boxes: {d}, {d}\n", .{ box1, box2 });

    std.debug.print("Scene setup complete. Total entities: {d}\n", .{engine.getEntityCount()});
    std.debug.print("Total physics bodies: {d}\n", .{engine.getPhysicsWorld().getBodyCount()});
}
