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

const GameScene = struct {
    // Scene data is part of the scene itself
    player_body_id: ?usize = null,
    input_mgr: *zixel.input.KeybindManager(PlayerAction) = undefined, // Set in main

    // Optional configuration - defaults are applied automatically
    const config = .{
        .needs_physics = true,
        .auto_update_physics = true,
        // No camera config - uses defaults
        // No input manager name - input is handled directly via scene data
    };

    pub fn init(self: *GameScene, ctx: *zixel.SceneContext) !void {
        // Create controllable player (bigger circle)
        const player_radius = 20;
        self.player_body_id = try ctx.physics().?.addBody(Body.initDynamic(.{ .circle = .{ .radius = player_radius } }, Vector2.init(200, 100), .{
            .mass = 1.0,
            .restitution = 0.3,
            .friction = 0.8,
        }));

        // Create platforms
        // Main angled platform
        const platform1 = Rectangle.init(0, 0, 300, 30);
        _ = try ctx.physics().?.addBody(Body.initStatic(.{ .rectangle = platform1 }, Vector2.init(400, 400), .{
            .rotation = std.math.degreesToRadians(-15.0),
        }));

        // Ground platform
        const ground = Rectangle.init(0, 0, 800, 40);
        _ = try ctx.physics().?.addBody(Body.initStatic(.{ .rectangle = ground }, Vector2.init(640, 680), .{}));

        // Left platform
        const left_platform = Rectangle.init(0, 0, 200, 20);
        _ = try ctx.physics().?.addBody(Body.initStatic(.{ .rectangle = left_platform }, Vector2.init(150, 300), .{}));

        // Right platform
        const right_platform = Rectangle.init(0, 0, 150, 20);
        _ = try ctx.physics().?.addBody(Body.initStatic(.{ .rectangle = right_platform }, Vector2.init(900, 250), .{
            .rotation = std.math.degreesToRadians(10.0),
        }));

        // Log the creation with our new system
        logging.physics.info("Created player circle with radius: {d} and {} platforms", .{ player_radius, 4 });
    }

    pub fn deinit(self: *GameScene, ctx: *zixel.SceneContext) void {
        _ = self;
        _ = ctx;
        logging.general.info("Game scene deinitialized", .{});
    }

    pub fn update(self: *GameScene, ctx: *zixel.SceneContext, dt: f32) !void {
        _ = dt;

        if (self.player_body_id) |body_id| {
            var body = ctx.physics().?.getBodyById(body_id) orelse return;

            // Movement with our clean input system
            if (self.input_mgr.isActionHeld(.move_left)) {
                body.applyForce(.{ .x = -500, .y = 0 });
            }
            if (self.input_mgr.isActionHeld(.move_right)) {
                body.applyForce(.{ .x = 500, .y = 0 });
            }
            if (self.input_mgr.isActionTapped(.jump)) {
                body.applyForce(.{ .x = 0, .y = -5000 });
            }
        } else {
            logging.general.warn("Player body {?} not found!", .{self.player_body_id});
        }
    }

    pub fn render(self: *GameScene, ctx: *zixel.SceneContext) !void {
        const world = ctx.physics().?;

        for (world.bodies.items) |body| {
            // Highlight the player body in blue, others in red/green
            var color: zixel.rl.Color = undefined;
            if (body.id == self.player_body_id) {
                color = zixel.rl.Color.blue; // Player is blue
            } else if (body.kind == .dynamic) {
                color = zixel.rl.Color.red; // Other dynamic bodies are red
            } else {
                color = zixel.rl.Color.green; // Static bodies are green
            }

            body.draw(color);

            // Draw a selection ring around the player with a small margin
            if (body.id == self.player_body_id) {
                const pos = body.getPosition();
                const shape = body.getShape();
                const ring_radius: f32 = switch (shape) {
                    .circle => |c| c.radius + 4.0,
                    .rectangle => |r| @max(r.width, r.height) / 2.0 + 4.0,
                };
                zixel.rl.drawCircleLinesV(pos, ring_radius, zixel.Color.yellow);
            }
        }

        // Draw controls info showing different input behaviors
        zixel.rl.drawText("Perfect Scene API - Self-Contained!", 10, 10, 20, zixel.Color.black);
        zixel.rl.drawText("Arrow Keys: Move (HOLD)", 10, 35, 16, zixel.Color.dark_gray);
        zixel.rl.drawText("Space: Jump (TAP)", 10, 55, 16, zixel.Color.dark_gray);
        zixel.rl.drawText("J: Hold to charge, release to attack", 10, 75, 16, zixel.Color.dark_gray);
        zixel.rl.drawText("E: Interact (TAP + consumed)", 10, 95, 16, zixel.Color.dark_gray);
        zixel.rl.drawText("G: Toggle Debug", 10, 115, 16, zixel.Color.dark_gray);

        // Show which body is controlled
        const player_info = std.fmt.allocPrintZ(ctx.engine.alloc, "Controlling Body ID: {?}", .{self.player_body_id}) catch "Player: ?";
        defer ctx.engine.alloc.free(player_info);
        zixel.rl.drawText(@ptrCast(player_info), 10, 135, 16, zixel.Color.blue);
    }
};

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

    var input_mgr = zixel.input.KeybindManager(PlayerAction).init(allocator);
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
            .title = "Scene API Demo",
        },
        .physics = .{
            .gravity = Vector2{ .x = 0, .y = 400 },
            .debug_draw_aabb = false,
            .debug_draw_contacts = true,
        },
    });

    defer game.deinit();

    // Set the input manager on the engine
    game.setInputManager(&input_mgr);

    const window = game.window;
    const window_size = window.getSize();
    logging.general.info("Window size: {}x{}", .{ window_size.windowWidth, window_size.windowHeight });

    try game.registerScene("game", GameScene);

    if (game.getSceneInstance("game", GameScene)) |game_scene| {
        game_scene.input_mgr = &input_mgr;
    }

    // Start the game scene
    try game.switchToScene("game");

    try game.run();
}
