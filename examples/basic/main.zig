const std = @import("std");
const zixel = @import("zixel");
const Engine = zixel.engine.Engine;
const Rectangle = zixel.Rectangle;
const Body = zixel.Body;
const Vector2 = zixel.Vector2;
const DynamicBody = zixel.DynamicBody;
const logging = zixel.logging;
const Allocator = std.mem.Allocator;

const EngineConfig = zixel.engine.EngineConfig;
const WindowConfig = zixel.WindowConfig;

const PlayerAction = enum {
    move_left,
    move_right,
    move_up,
    move_down,
    jump,
    attack,
    interact,
};

// Global variable to track the controllable body
var player_body_id: ?usize = null;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logging system and test build options
    logging.init();

    // Test different log levels and build options
    logging.general.info("Build options test - Debug enabled: {}, Profiling: {}, Physics debug: {}", .{ logging.isDebugEnabled(), logging.isProfilingEnabled(), logging.isPhysicsDebugEnabled() });

    logging.debugProfile("This is a profile debug message: {s}", .{"test"});
    logging.debugPhysics("This is a physics debug message: {s}", .{"test"});

    var input_mgr = zixel.input.InputManager(PlayerAction).init(allocator);
    defer input_mgr.deinit();

    // Bind keys directly to the input manager
    try input_mgr.bindMany(.{
        .move_left = zixel.input.Key.left,
        .move_right = zixel.input.Key.right,
        .move_up = zixel.input.Key.up,
        .move_down = zixel.input.Key.down,
        .jump = zixel.input.Key.space,
        .attack = zixel.input.Key.j,
        .interact = zixel.input.Key.e,
    });

    // Default engine config
    var game = Engine.init(allocator, .{
        .window = WindowConfig{
            .width = 1280,
            .height = 720,
            .title = "Zixel - Custom Input Example",
        },
        .physics = .{
            .gravity = Vector2{ .x = 0, .y = 400 },
            .debug_draw_aabb = false,
            .debug_draw_contacts = true,
        },
    });

    defer game.deinit();

    // Set callbacks using direct field assignment (no setters needed)
    game.update_game = gameUpdate;
    game.render_game = gameRender;

    // Set the input manager on the engine
    game.setInputManager(&input_mgr);

    const window = game.window;
    const window_size = window.getSize();
    logging.general.info("Window size: {}x{}", .{ window_size.windowWidth, window_size.windowHeight });

    // Create controllable player (bigger circle)
    const player_radius = 20;
    player_body_id = try game.physics.addBody(Body.initDynamic(.{ .circle = .{ .radius = player_radius } }, Vector2.init(200, 100), .{
        .mass = 1.0,
        .restitution = 0.3,
        .friction = 0.8,
    }));

    // Create platforms
    // Main angled platform
    const platform1 = Rectangle.init(0, 0, 300, 30);
    _ = try game.physics.addBody(Body.initStatic(.{ .rectangle = platform1 }, Vector2.init(400, 400), .{
        .rotation = std.math.degreesToRadians(-15.0),
    }));

    // Ground platform
    const ground = Rectangle.init(0, 0, 800, 40);
    _ = try game.physics.addBody(Body.initStatic(.{ .rectangle = ground }, Vector2.init(640, 680), .{}));

    // Left platform
    const left_platform = Rectangle.init(0, 0, 200, 20);
    _ = try game.physics.addBody(Body.initStatic(.{ .rectangle = left_platform }, Vector2.init(150, 300), .{}));

    // Right platform
    const right_platform = Rectangle.init(0, 0, 150, 20);
    _ = try game.physics.addBody(Body.initStatic(.{ .rectangle = right_platform }, Vector2.init(900, 250), .{
        .rotation = std.math.degreesToRadians(10.0),
    }));

    // Log the creation with our new system
    logging.physics.info("Created player circle with radius: {d} and {} platforms", .{ player_radius, 4 });

    try game.run();
}

fn gameUpdate(engine: *Engine, allocator: Allocator, dt: f32) !void {
    _ = dt; // Suppress unused parameter warning
    _ = allocator; // Suppress unused parameter warning

    // Handle input in the update function
    var input_mgr = engine.getInputManager(zixel.input.InputManager(PlayerAction));

    if (player_body_id) |body_id| {
        var body = engine.physics.getBodyById(body_id) orelse return;

        // Movement with our clean input system
        if (input_mgr.isActionHeld(.move_left)) {
            body.applyForce(.{ .x = -500, .y = 0 });
        }
        if (input_mgr.isActionHeld(.move_right)) {
            body.applyForce(.{ .x = 500, .y = 0 });
        }
        if (input_mgr.isActionTapped(.jump)) {
            body.applyForce(.{ .x = 0, .y = -1000 });
        }
    } else {
        logging.general.warn("Player body {?} not found!", .{player_body_id});
    }
}

fn gameRender(engine: *Engine, alloc: Allocator) !void {
    const world = engine.physics;

    for (world.bodies.items) |*body| {
        // Highlight the player body in blue, others in red/green
        var color: zixel.rl.Color = undefined;
        if (body.id == player_body_id) {
            color = zixel.rl.Color.blue; // Player is blue
        } else if (body.*.kind == .Dynamic) {
            color = zixel.rl.Color.red; // Other dynamic bodies are red
        } else {
            color = zixel.rl.Color.green; // Static bodies are green
        }

        body.draw(color);

        // Draw a selection ring around the player
        if (body.id == player_body_id) {
            const pos = body.getPosition();
            zixel.rl.drawCircleLinesV(pos, 35, zixel.rl.Color.yellow);
        }
    }

    // Draw controls info showing different input behaviors
    zixel.rl.drawText("Custom Input Demo (User-Defined Enum):", 10, 10, 20, zixel.rl.Color.black);
    zixel.rl.drawText("Arrow Keys: Move (HOLD)", 10, 35, 16, zixel.rl.Color.dark_gray);
    zixel.rl.drawText("Space: Jump (TAP)", 10, 55, 16, zixel.rl.Color.dark_gray);
    zixel.rl.drawText("J: Hold to charge, release to attack", 10, 75, 16, zixel.rl.Color.dark_gray);
    zixel.rl.drawText("E: Interact (TAP + consumed)", 10, 95, 16, zixel.rl.Color.dark_gray);
    zixel.rl.drawText("G: Toggle Debug", 10, 115, 16, zixel.rl.Color.dark_gray);

    // Show which body is controlled
    const player_info = std.fmt.allocPrintZ(alloc, "Controlling Body ID: {?}", .{player_body_id}) catch "Player: ?";
    defer alloc.free(player_info);
    zixel.rl.drawText(@ptrCast(player_info), 10, 135, 16, zixel.rl.Color.blue);
}
