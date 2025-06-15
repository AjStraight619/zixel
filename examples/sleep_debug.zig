const std = @import("std");
const zixel = @import("zixel");
const Engine = zixel.engine.Engine;
const Body = zixel.Body;
const Vector2 = zixel.Vector2;
const Rectangle = zixel.Rectangle;
const Allocator = std.mem.Allocator;
const logging = zixel.logging;

var ball_id: usize = undefined;
var ground_id: usize = undefined;
var time_elapsed: f32 = 0.0;

fn gameUpdate(engine: *Engine, allocator: Allocator, dt: f32) !void {
    _ = allocator;
    time_elapsed += dt;

    // Add impulse when spacebar is pressed
    if (zixel.rl.isKeyPressed(.space)) {
        const ball_body = engine.physics.getBodyById(ball_id).?;
        ball_body.wakeUp();
        ball_body.kind.Dynamic.velocity.x += 100.0;
        logging.physics.info("SPACEBAR: Applied impulse and woke up ball!", .{});
    }

    // Reset ball position when R is pressed
    if (zixel.rl.isKeyPressed(.r)) {
        const ball_body = engine.physics.getBodyById(ball_id).?;
        ball_body.wakeUp();
        ball_body.kind.Dynamic.position = Vector2{ .x = 400, .y = 100 };
        ball_body.kind.Dynamic.velocity = Vector2{ .x = 0, .y = 0 };
        ball_body.kind.Dynamic.angular_velocity = 0.0;
        logging.physics.info("RESET: Ball position and velocity reset!", .{});
    }

    // Toggle sleep system when T is pressed
    if (zixel.rl.isKeyPressed(.t)) {
        engine.physics.config.allow_sleeping = !engine.physics.config.allow_sleeping;
        logging.physics.info("TOGGLE: Sleep system now {s}", .{if (engine.physics.config.allow_sleeping) "ENABLED" else "DISABLED"});
    }

    // Adjust sleep thresholds with number keys
    if (zixel.rl.isKeyPressed(.one)) {
        engine.physics.config.sleep_velocity_threshold = 1.0;
        logging.physics.info("Sleep velocity threshold set to 1.0", .{});
    }
    if (zixel.rl.isKeyPressed(.two)) {
        engine.physics.config.sleep_velocity_threshold = 5.0;
        logging.physics.info("Sleep velocity threshold set to 5.0", .{});
    }
    if (zixel.rl.isKeyPressed(.three)) {
        engine.physics.config.sleep_velocity_threshold = 15.0;
        logging.physics.info("Sleep velocity threshold set to 15.0 (default)", .{});
    }
    if (zixel.rl.isKeyPressed(.four)) {
        engine.physics.config.sleep_time_threshold = 1.0;
        logging.physics.info("Sleep time threshold set to 1.0s", .{});
    }
    if (zixel.rl.isKeyPressed(.five)) {
        engine.physics.config.sleep_time_threshold = 3.0;
        logging.physics.info("Sleep time threshold set to 3.0s", .{});
    }
    if (zixel.rl.isKeyPressed(.six)) {
        engine.physics.config.sleep_time_threshold = 5.0;
        logging.physics.info("Sleep time threshold set to 5.0s (default)", .{});
    }
}

fn gameRender(engine: *Engine, allocator: Allocator) !void {
    _ = allocator;

    zixel.rl.clearBackground(zixel.rl.Color.dark_gray);

    // Draw all bodies
    for (engine.physics.bodies.items) |*body| {
        const color = if (body.id == ball_id and body.isSleeping()) zixel.rl.Color.red else zixel.rl.Color.white;
        body.draw(color);
    }

    // Draw sleep state indicator
    const ball = engine.physics.getBodyById(ball_id).?;
    const ball_pos = ball.kind.Dynamic.position;

    if (ball.isSleeping()) {
        // Draw "ZZZ" above sleeping ball
        zixel.rl.drawText("ZZZ", @intFromFloat(ball_pos.x - 15), @intFromFloat(ball_pos.y - 50), 20, zixel.rl.Color.white);
        // Draw red circle around sleeping ball
        zixel.rl.drawCircleLines(@intFromFloat(ball_pos.x), @intFromFloat(ball_pos.y), 35, zixel.rl.Color.red);
    } else {
        // Draw green circle around awake ball
        zixel.rl.drawCircleLines(@intFromFloat(ball_pos.x), @intFromFloat(ball_pos.y), 35, zixel.rl.Color.green);
    }

    // Draw velocity vector
    const dyn_body = &ball.kind.Dynamic;
    const vel_scale = 0.1;
    const vel_end = Vector2{
        .x = ball_pos.x + dyn_body.velocity.x * vel_scale,
        .y = ball_pos.y + dyn_body.velocity.y * vel_scale,
    };
    zixel.rl.drawLineV(ball_pos, vel_end, zixel.rl.Color.yellow);

    // Draw UI
    zixel.rl.drawText("Sleep Debug Test", 10, 10, 20, zixel.rl.Color.white);
    zixel.rl.drawText("SPACE: Add impulse", 10, 40, 16, zixel.rl.Color.light_gray);
    zixel.rl.drawText("R: Reset ball", 10, 60, 16, zixel.rl.Color.light_gray);
    zixel.rl.drawText("T: Toggle sleep system", 10, 80, 16, zixel.rl.Color.light_gray);
    zixel.rl.drawText("1-3: Velocity threshold (1, 5, 15)", 10, 100, 16, zixel.rl.Color.light_gray);
    zixel.rl.drawText("4-6: Time threshold (1s, 3s, 5s)", 10, 120, 16, zixel.rl.Color.light_gray);

    // Draw current settings
    const settings_y = 160;
    zixel.rl.drawText("Current Settings:", 10, settings_y, 16, zixel.rl.Color.white);

    const sleep_enabled_text = if (engine.physics.config.allow_sleeping) "ENABLED" else "DISABLED";
    const sleep_enabled_color = if (engine.physics.config.allow_sleeping) zixel.rl.Color.green else zixel.rl.Color.red;
    zixel.rl.drawText(zixel.rl.textFormat("Sleep System: %s", .{sleep_enabled_text.ptr}), 10, settings_y + 20, 14, sleep_enabled_color);

    zixel.rl.drawText(zixel.rl.textFormat("Velocity Threshold: %.1f", .{engine.physics.config.sleep_velocity_threshold}), 10, settings_y + 40, 14, zixel.rl.Color.white);
    zixel.rl.drawText(zixel.rl.textFormat("Time Threshold: %.1fs", .{engine.physics.config.sleep_time_threshold}), 10, settings_y + 60, 14, zixel.rl.Color.white);

    // Draw ball state
    const ball_state_y = settings_y + 100;
    zixel.rl.drawText("Ball State:", 10, ball_state_y, 16, zixel.rl.Color.white);

    const sleeping_text = if (ball.isSleeping()) "SLEEPING" else "AWAKE";
    const sleeping_color = if (ball.isSleeping()) zixel.rl.Color.red else zixel.rl.Color.green;
    zixel.rl.drawText(zixel.rl.textFormat("Status: %s", .{sleeping_text.ptr}), 10, ball_state_y + 20, 14, sleeping_color);

    const velocity_mag = @sqrt(dyn_body.velocity.x * dyn_body.velocity.x +
        dyn_body.velocity.y * dyn_body.velocity.y);
    zixel.rl.drawText(zixel.rl.textFormat("Velocity: %.2f", .{velocity_mag}), 10, ball_state_y + 40, 14, zixel.rl.Color.white);
    zixel.rl.drawText(zixel.rl.textFormat("Sleep Timer: %.2fs", .{dyn_body.sleep_time}), 10, ball_state_y + 60, 14, zixel.rl.Color.white);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize engine with sleep-friendly physics config
    var engine = Engine.init(allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Sleep Debug Test",
        },
        .physics = .{
            .gravity = Vector2{ .x = 0, .y = 200 }, // Moderate gravity
            .allow_sleeping = true,
            .sleep_velocity_threshold = 5.0, // Lower threshold for easier testing
            .sleep_time_threshold = 3.0, // Shorter time for easier testing
            .restitution_clamp_threshold = 25.0, // Kill bounce if closing velocity is < this
        },
    });
    defer engine.deinit();

    // Set callbacks
    engine.update_game = gameUpdate;
    engine.render_game = gameRender;

    // Create ground
    const ground_rect = Rectangle.init(0, 0, 800, 50);
    ground_id = try engine.physics.addBody(Body.initStatic(.{ .rectangle = ground_rect }, Vector2{ .x = 400, .y = 550 }, .{
        .restitution = 0.3,
        .friction = 0.7,
    }));

    // Create ball
    ball_id = try engine.physics.addBody(Body.initDynamic(.{ .circle = .{ .radius = 20 } }, Vector2{ .x = 400, .y = 100 }, .{
        .mass = 1.0,
        .restitution = 0.6,
        .friction = 0.3,
    }));

    logging.physics.info("=== Sleep Debug Test Started ===", .{});
    logging.physics.info("Ball will fall and should go to sleep when it stops bouncing.", .{});
    logging.physics.info("Watch the console for detailed sleep state logging.", .{});
    logging.physics.info("Use controls to test different scenarios.", .{});

    // Run the engine
    try engine.run();
}
