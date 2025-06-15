const std = @import("std");
const zixel = @import("zixel");
const Engine = zixel.engine.Engine;
const Body = zixel.Body;
const Vector2 = zixel.Vector2;
const rl = @import("raylib");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize engine
    var engine = Engine.init(allocator, .{ .target_fps = 200 });
    defer engine.deinit();

    // Create a kinematic platform (moving platform)
    const kinematic_platform = Body.initKinematic(.{ .rectangle = .{ .x = 0, .y = 0, .width = 100, .height = 20 } }, Vector2.init(200, 300), .{
        .velocity = Vector2.init(50, 0), // Moving right at 50 units/sec
        .friction = 0.8, // High friction to grip objects
    });

    // Create a dynamic ball that will be pushed by the platform
    const dynamic_ball = Body.initDynamic(.{ .circle = .{ .radius = 15 } }, Vector2.init(250, 250), .{
        .mass = 1.0,
        .restitution = 0.3,
    });

    // Create static walls
    const left_wall = Body.initStatic(.{ .rectangle = .{ .x = 0, .y = 0, .width = 10, .height = 600 } }, Vector2.init(5, 300), .{});

    const right_wall = Body.initStatic(.{ .rectangle = .{ .x = 0, .y = 0, .width = 10, .height = 600 } }, Vector2.init(795, 300), .{});

    // Add bodies to physics world
    _ = try engine.physics.addBody(kinematic_platform);
    _ = try engine.physics.addBody(dynamic_ball);
    _ = try engine.physics.addBody(left_wall);
    _ = try engine.physics.addBody(right_wall);

    // Set the callback functions
    engine.setUpdateFn(gameUpdate);
    engine.setRenderFn(gameRender);

    // Run the simulation
    try engine.run();
}

fn gameUpdate(engine: *Engine, alloc: std.mem.Allocator, deltaTime: f32) !void {
    // Get the kinematic platform and reverse its direction when it hits walls
    if (engine.physics.getBodyById(0)) |platform_body| {
        const platform_pos = platform_body.getPosition();

        // Reverse direction when hitting walls
        if (platform_pos.x <= 60 or platform_pos.x >= 740) {
            if (platform_body.isKinematic()) {
                platform_body.kind.Kinematic.velocity.x *= -1;
            }
        }
    }

    _ = alloc; // Suppress unused parameter warning
    _ = deltaTime; // Suppress unused parameter warning
}

fn gameRender(engine: *Engine, alloc: std.mem.Allocator) !void {
    _ = alloc; // Suppress unused parameter warning
    rl.clearBackground(rl.Color.black);

    // Draw all bodies with different colors
    const bodies = engine.physics.bodies.items;
    for (bodies) |*body| {
        const color = switch (body.kind) {
            .Static => rl.Color.white,
            .Dynamic => rl.Color.red,
            .Kinematic => rl.Color.green,
        };
        body.draw(color);
    }

    // Draw instructions
    rl.drawText("Kinematic Body Test", 10, 10, 20, rl.Color.yellow);
    rl.drawText("Green = Kinematic Platform", 10, 35, 16, rl.Color.green);
    rl.drawText("Red = Dynamic Ball", 10, 55, 16, rl.Color.red);
    rl.drawText("White = Static Walls", 10, 75, 16, rl.Color.white);
    rl.drawText("Platform pushes ball but isn't affected by collisions", 10, 95, 14, rl.Color.gray);
}
