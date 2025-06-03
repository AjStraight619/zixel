const std = @import("std");
const zixel = @import("zixel");

var ball_spawned: bool = false;
var engine_ptr: *zixel.Engine = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the ECS engine
    var engine = try zixel.Engine.init(allocator, .{
        .window_width = 1000,
        .window_height = 700,
        .window_title = "Ball Rolling Down Ramps - Press SPACE to Drop Ball!",
        .target_fps = 60,
    });
    defer engine.deinit();

    engine_ptr = &engine;

    // Create angled ramps for the ball to roll down

    // Ramp 1: Top left, angled down-right
    const ramp1_shape = zixel.PhysicsShape{ .rectangle = zixel.rl.Rectangle.init(0, 0, 200, 20) };
    _ = try engine.createStaticBody(zixel.components.Transform{
        .position = zixel.rl.Vector2.init(200, 200),
        .rotation = 15.0 * std.math.pi / 180.0, // 15 degrees in radians
    }, ramp1_shape, zixel.rl.Color.brown);

    // Ramp 2: Middle, steeper angle
    const ramp2_shape = zixel.PhysicsShape{ .rectangle = zixel.rl.Rectangle.init(0, 0, 180, 20) };
    _ = try engine.createStaticBody(zixel.components.Transform{
        .position = zixel.rl.Vector2.init(450, 320),
        .rotation = 25.0 * std.math.pi / 180.0, // 25 degrees
    }, ramp2_shape, zixel.rl.Color.dark_brown);

    // Ramp 3: Lower right, gentler slope
    const ramp3_shape = zixel.PhysicsShape{ .rectangle = zixel.rl.Rectangle.init(0, 0, 220, 20) };
    _ = try engine.createStaticBody(zixel.components.Transform{
        .position = zixel.rl.Vector2.init(650, 450),
        .rotation = 10.0 * std.math.pi / 180.0, // 10 degrees
    }, ramp3_shape, zixel.rl.Color.gray);

    // Ground platform at the bottom
    const ground_shape = zixel.PhysicsShape{ .rectangle = zixel.rl.Rectangle.init(0, 0, 1000, 30) };
    _ = try engine.createStaticBody(zixel.components.Transform{ .position = zixel.rl.Vector2.init(500, 650) }, ground_shape, zixel.rl.Color.dark_gray);

    // Left wall to contain the ball
    const left_wall_shape = zixel.PhysicsShape{ .rectangle = zixel.rl.Rectangle.init(0, 0, 20, 700) };
    _ = try engine.createStaticBody(zixel.components.Transform{ .position = zixel.rl.Vector2.init(10, 350) }, left_wall_shape, zixel.rl.Color.black);

    // Right wall to contain the ball
    const right_wall_shape = zixel.PhysicsShape{ .rectangle = zixel.rl.Rectangle.init(0, 0, 20, 700) };
    _ = try engine.createStaticBody(zixel.components.Transform{ .position = zixel.rl.Vector2.init(990, 350) }, right_wall_shape, zixel.rl.Color.black);

    // Create instruction text
    _ = try engine.createText(zixel.rl.Vector2.init(350, 50), "Press SPACE to drop the ball!", 30);

    std.debug.print("Rolling Ball Demo Setup Complete!\n", .{});
    std.debug.print("- 3 angled ramps with different slopes\n", .{});
    std.debug.print("- Press SPACE to drop the red ball and watch it roll!\n", .{});
    std.debug.print("- Press ESC to exit\n", .{});

    // Custom system to handle ball spawning
    try engine.addSystem(struct {
        fn ballSpawnSystem(world: *zixel.World, dt: f32) !void {
            _ = world;
            _ = dt;

            // Handle spacebar to spawn ball
            if (!ball_spawned and zixel.rl.isKeyPressed(.space)) {
                std.debug.print("SPAWNING BALL! Watch it roll down the ramps!\n", .{});

                // Create a dynamic ball (affected by gravity and physics) - starts at top left
                const ball_shape = zixel.PhysicsShape{ .circle = .{ .radius = 15 } };
                const ball_entity = try engine_ptr.createDynamicBody(zixel.components.Transform{ .position = zixel.rl.Vector2.init(120, 100) }, ball_shape, zixel.rl.Color.red);

                // DEBUG: Check the ball's physics properties
                if (engine_ptr.getComponent(zixel.components.PhysicsBodyRef, ball_entity)) |physics_ref| {
                    const physics_world = engine_ptr.getPhysicsWorld();
                    if (physics_world.getBody(physics_ref.body_id)) |body| {
                        std.debug.print("BALL PHYSICS DEBUG:\n", .{});
                        std.debug.print("  Body type: {}\n", .{body.kind});
                        if (body.isDynamic()) {
                            const dyn = &body.kind.Dynamic;
                            std.debug.print("  Mass: {d:.2}\n", .{dyn.mass});
                            std.debug.print("  Gravity scale: {d:.2}\n", .{dyn.gravity_scale});
                            std.debug.print("  Position: ({d:.1}, {d:.1})\n", .{ dyn.position.x, dyn.position.y });
                            std.debug.print("  Velocity: ({d:.1}, {d:.1})\n", .{ dyn.velocity.x, dyn.velocity.y });
                        }

                        // Also check physics world gravity
                        const gravity = physics_world.config.gravity;
                        std.debug.print("  World gravity: ({d:.1}, {d:.1})\n", .{ gravity.x, gravity.y });
                    } else {
                        std.debug.print("ERROR: Could not get physics body for ball!\n", .{});
                    }
                } else {
                    std.debug.print("ERROR: Ball has no physics body reference!\n", .{});
                }

                ball_spawned = true;
            }
        }
    }.ballSpawnSystem);

    // Use the engine's built-in run method
    try engine.run();
}
