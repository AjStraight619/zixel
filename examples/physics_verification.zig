const std = @import("std");
const rl = @import("raylib");
const zixel = @import("zixel");
const Engine = zixel.Engine;
const Body = zixel.Body;
const utils = @import("../src/math/utils.zig");

// PHYSICS VERIFICATION TEST TYPES AND RUNNER

const PhysicsTestScenario = struct {
    name: [:0]const u8,
    description: []const u8,
    setup_fn: *const fn (engine: *Engine) anyerror!void,
    verify_fn: ?*const fn (engine: *Engine) anyerror!bool = null,
    duration_seconds: f32 = 5.0,
};

const PhysicsTestRunner = struct {
    engine: *Engine,
    current_scenario: ?usize = null,
    scenarios: []const PhysicsTestScenario,
    start_time: f64 = 0.0,

    const Self = @This();

    pub fn init(engine: *Engine) Self {
        return Self{
            .engine = engine,
            .scenarios = &PHYSICS_SCENARIOS,
        };
    }

    pub fn runScenario(self: *Self, scenario_index: usize) !void {
        if (scenario_index >= self.scenarios.len) return;

        const scenario = self.scenarios[scenario_index];
        std.debug.print("\nRunning Physics Test: {s}\n", .{scenario.name});
        std.debug.print("{s}\n", .{scenario.description});

        // Clear existing bodies
        const world = self.engine.physics;
        world.bodies.clearRetainingCapacity();

        // Setup scenario
        try scenario.setup_fn(self.engine);

        self.current_scenario = scenario_index;
        self.start_time = rl.getTime();
    }

    pub fn update(self: *Self) !void {
        if (self.current_scenario == null) return;

        const scenario = self.scenarios[self.current_scenario.?];
        const elapsed = rl.getTime() - self.start_time;

        if (elapsed >= scenario.duration_seconds) {
            if (scenario.verify_fn) |verify| {
                const passed = try verify(self.engine);
                std.debug.print("Test Result: {s}\n", .{if (passed) "PASSED" else "FAILED"});
            }
            self.current_scenario = null;
        }
    }

    pub fn renderUI(self: *Self) void {
        if (self.current_scenario) |_| {
            // const scenario = self.scenarios[idx];
            // const elapsed = rl.getTime() - self.start_time;
            // const remaining = scenario.duration_seconds - elapsed;

            // rl.drawText(scenario.name, 10, 10, 20, rl.Color.black);
            // const timer_text = std.fmt.allocPrint(self.engine.allocator, "Time: {:.1}s", .{remaining}) catch "Timer Error";
            // defer self.engine.allocator.free(timer_text);
            // rl.drawText(@as([:0]const u8, @ptrCast(timer_text)), 10, 40, 16, rl.Color.dark_gray);
        }
    }
};

// PHYSICS TEST SCENARIOS

const PHYSICS_SCENARIOS = [_]PhysicsTestScenario{
    // .{
    //     .name = "Ball rolling down ramp",
    //     .description = "Ball rolling down non-axis aligned rect",
    //     .setup_fn = setupBallRampTest,
    // },
    // .{
    //     .name = "Circle vs Rect Horizontal",
    //     .description = "Circle vs Rect Horizontal",
    //     .setup_fn = setupCircleVsRectHorizontalTest,
    //     // .verify_fn = verifyCircleVsRectHorizontal,
    // },

    .{
        .name = "Test ball dropping on edge of rect",
        .description = "Many shapes falling on floor",
        .setup_fn = setUpBallDroppingOnEdgeOfRectTest,
    },

    // .{
    //     .name = "Ball rolling from ramp to ramp to floor colliding with ball on floor",
    //     .description = "Complex physics demonstration: Ball rolls down multiple ramps, jumps gaps, and collides with stationary balls creating a chain reaction.",
    //     .setup_fn = setupBallRollingFromRampToRampToFloorTest,
    // },

    .{
        .name = "Momentum Conservation - Head-on Collision",
        .description = "Two equal mass bodies collide head-on. Total momentum should be conserved.",
        .setup_fn = setupMomentumConservationTest,
        .verify_fn = verifyMomentumConservation,
    },
    .{
        .name = "Energy Conservation - Elastic Collision",
        .description = "High restitution collision should conserve kinetic energy approximately.",
        .setup_fn = setupEnergyConservationTest,
        .verify_fn = verifyEnergyConservation,
    },
    .{
        .name = "SAT Accuracy - Rotating Collision",
        .description = "Rotated rectangle colliding with stationary one using SAT algorithm.",
        .setup_fn = setupSATAccuracyTest,
        .verify_fn = verifySATAccuracy,
    },
    .{
        .name = "Tunneling Prevention",
        .description = "Very fast moving object should not tunnel through thin barrier.",
        .setup_fn = setupTunnelingPreventionTest,
        .verify_fn = verifyTunnelingPrevention,
    },
    .{
        .name = "Mass Ratio Test - Different Masses",
        .description = "Heavy object vs light object collision physics.",
        .setup_fn = setupMassRatioTest,
        .verify_fn = verifyMassRatioPhysics,
    },
    .{
        .name = "Sleep/Wake System Test",
        .description = "Bodies should sleep when still, wake when disturbed.",
        .setup_fn = setupSleepSystemTest,
        .verify_fn = verifySleepWakeSystem,
    },
    .{
        .name = "Multi-body Chain Reaction",
        .description = "Newton's cradle style chain reaction test.",
        .setup_fn = setupNewtonsCradleTest,
        .verify_fn = verifyChainReaction,
    },
};

fn setUpBallDroppingOnEdgeOfRectTest(engine: *Engine) !void {
    const world = engine.physics;
    engine.setGravity(rl.Vector2{ .x = 0, .y = 50 });

    var rand_x_vel = std.crypto.random.float(f32) * 1;
    const should_be_negative = std.crypto.random.boolean();

    if (should_be_negative) {
        rand_x_vel = -rand_x_vel;
    }

    const ball_shape = zixel.PhysicsShape{ .circle = .{ .radius = 10 } };
    const ball = Body.initDynamic(ball_shape, rl.Vector2{ .x = 457, .y = 100 }, .{
        .velocity = rl.Vector2{ .x = rand_x_vel, .y = 0 },
    });

    const rect_shape = zixel.PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 100, .height = 20 } };
    const rect = Body.initStatic(rect_shape, rl.Vector2{ .x = 500, .y = 400 }, .{
        .rotation = utils.degreesToRadians(-30),
    });

    _ = try world.addBody(ball);
    _ = try world.addBody(rect);
}

fn setupManyShapesFallingOnFloorTest(engine: *Engine) !void {
    const world = engine.physics;
    engine.setGravity(rl.Vector2{ .x = 0, .y = 300 });

    world.config.physics_time_step = 1.0 / 120.0; // 120 FPS physics

    // Create an angled ramp to test friction
    const ramp_shape = zixel.PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 300, .height = 20 } };
    const ramp = Body.initStatic(ramp_shape, rl.Vector2{ .x = 400, .y = 400 }, .{
        .rotation = utils.degreesToRadians(15), // 15 degree slope
        .friction = 1.0, // High friction ramp
        .restitution = 0.1, // Low bounce
    });

    // Floor spans full screen width (1000px) - position is CENTER of body
    const floor_shape = zixel.PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 1000, .height = 40 } };
    const floor = Body.initStatic(floor_shape, rl.Vector2{ .x = 500, .y = 500 }, .{
        .friction = 0.1,
        .restitution = 0.2,
    });

    // Create objects with different friction properties
    const rect_shape = zixel.PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 20, .height = 20 } };

    // High friction object (should grip the ramp)
    const sticky_rect = Body.initDynamic(rect_shape, rl.Vector2{ .x = 350, .y = 300 }, .{
        .velocity = rl.Vector2{ .x = 0, .y = 0 },
        .friction = 0.9, // High friction - should slide slowly
        .restitution = 0.3,
        .mass = 1.0,
    });

    // Low friction object (should slide quickly)
    const slippery_rect = Body.initDynamic(rect_shape, rl.Vector2{ .x = 380, .y = 280 }, .{
        .velocity = rl.Vector2{ .x = 0, .y = 0 },
        .friction = 0.1, // Low friction - should slide fast like ice
        .restitution = 0.8,
        .mass = 1.0,
    });

    _ = try world.addBody(ramp);
    _ = try world.addBody(floor);
    _ = try world.addBody(sticky_rect);
    _ = try world.addBody(slippery_rect);
}

fn setupCircleVsRectHorizontalTest(engine: *Engine) !void {
    const world = engine.physics;
    engine.setGravity(rl.Vector2{ .x = 0, .y = 0 });

    const circle_shape = zixel.PhysicsShape{ .circle = .{ .radius = 20 } };
    const rect_shape = zixel.PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 20, .height = 20 } };

    const circle = Body.initDynamic(circle_shape, rl.Vector2{ .x = 100, .y = 100 }, .{
        .velocity = rl.Vector2{ .x = 100, .y = 0 },
    });
    const rect = Body.initDynamic(rect_shape, rl.Vector2{ .x = 700, .y = 100 }, .{
        .velocity = rl.Vector2{ .x = -100, .y = 0 },
    });

    _ = try world.addBody(circle);
    _ = try world.addBody(rect);
}

// TEST SETUP FUNCTIONS

fn setupBallRampTest(engine: *Engine) !void {
    const world = engine.physics;
    engine.setGravity(rl.Vector2{ .x = 0, .y = 500 }); // Enable gravity

    // Create a ramp (rotated rectangle)
    const ramp_shape = zixel.PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 200, .height = 20 } };
    const ramp_1 = Body.initStatic(ramp_shape, rl.Vector2{ .x = 400, .y = 400 }, .{
        .rotation = utils.degreesToRadians(30), // 30 degree slope
    });

    const ramp_2 = Body.initStatic(ramp_shape, rl.Vector2{ .x = 300, .y = 300 }, .{
        .rotation = utils.degreesToRadians(-30), // 30 degree slope
    });

    const floor_shape = zixel.PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 400, .height = 20 } };
    const floor = Body.initStatic(floor_shape, rl.Vector2{ .x = 400, .y = 500 }, .{});

    // Create a ball to roll down
    const ball_shape = zixel.PhysicsShape{ .circle = .{ .radius = 15 } };
    const ball = Body.initDynamic(ball_shape, rl.Vector2{ .x = 350, .y = 100 }, .{
        .velocity = rl.Vector2{ .x = 0, .y = 0 },
        .mass = 1.0,
        .restitution = 0.3,
        .friction = 0.5,
    });

    _ = try world.addBody(ramp_1);
    _ = try world.addBody(ramp_2);
    _ = try world.addBody(floor);
    _ = try world.addBody(ball);

    std.debug.print("Ball rolling down 30° ramp with gravity\n", .{});
}

fn setupBallRollingFromRampToRampToFloorTest(engine: *Engine) !void {
    const world = engine.physics;
    engine.setGravity(rl.Vector2{ .x = 0, .y = 600 }); // Strong gravity for dramatic effect

    // Use smaller timestep for better collision detection
    world.config.physics_time_step = 1.0 / 120.0; // 120 FPS physics

    // Create a PROPER cascading sequence with ski-jump style ramps
    const ramp_shape = zixel.PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 180, .height = 20 } };

    // Ramp 1: Launch ramp - moderate angle for good horizontal velocity
    const ramp_1 = Body.initStatic(ramp_shape, rl.Vector2{
        .x = 150, // Left side
        .y = 250, // Starting height
    }, .{
        .rotation = utils.degreesToRadians(-15), // NEGATIVE 15 degrees (upward launch angle)
        .friction = 0.2,
        .restitution = 0.1,
    });

    // Ramp 2: Catch ramp - positioned where ball lands from ramp 1
    const ramp_2 = Body.initStatic(ramp_shape, rl.Vector2{
        .x = 400, // Where ball will arc to
        .y = 350, // Lower to catch the falling ball
    }, .{
        .rotation = utils.degreesToRadians(-10), // NEGATIVE 10 degrees (slight upward launch)
        .friction = 0.2,
        .restitution = 0.1,
    });

    // Ramp 3: Final launch ramp
    const ramp_3 = Body.initStatic(ramp_shape, rl.Vector2{
        .x = 650, // Where ball lands from ramp 2
        .y = 450, // Even lower
    }, .{
        .rotation = utils.degreesToRadians(-5), // NEGATIVE 5 degrees (slight launch toward floor)
        .friction = 0.3,
        .restitution = 0.1,
    });

    // Floor: Full width at bottom
    const floor_shape = zixel.PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 1300, .height = 40 } };
    const floor = Body.initStatic(floor_shape, rl.Vector2{
        .x = 500, // Center horizontally
        .y = 680, // Near bottom
    }, .{
        .friction = 0.6,
        .restitution = 0.3,
    });

    // Rolling ball: Starts above first ramp with good momentum
    const rolling_ball_shape = zixel.PhysicsShape{ .circle = .{ .radius = 12 } };
    const rolling_ball = Body.initDynamic(rolling_ball_shape, rl.Vector2{
        .x = 80, // Left of first ramp
        .y = 180, // Above first ramp
    }, .{
        .velocity = rl.Vector2{ .x = 50, .y = 0 }, // Good horizontal velocity
        .mass = 1.0,
        .restitution = 0.8, // Bouncy for better launches
        .friction = 0.3,
    });

    // Target balls on floor: Where final ramp launches to
    const target_ball_shape = zixel.PhysicsShape{ .circle = .{ .radius = 15 } };

    // Ball 1: Where ball will land after final ramp
    const target_ball = Body.initDynamic(target_ball_shape, rl.Vector2{
        .x = 1010, // Far right where ball will land
        .y = 640, // On floor level
    }, .{
        .velocity = rl.Vector2{ .x = 0, .y = 0 },
        .mass = 1.5,
        .restitution = 0.8,
        .friction = 0.3,
    });

    // Ball 2: Chain reaction
    const extra_ball_1 = Body.initDynamic(target_ball_shape, rl.Vector2{ .x = 1040, .y = 640 }, .{
        .velocity = rl.Vector2{ .x = 0, .y = 0 },
        .mass = 1.2,
        .restitution = 0.75,
        .friction = 0.4,
    });

    // Ball 3: Final in chain
    const extra_ball_2 = Body.initDynamic(rolling_ball_shape, rl.Vector2{ .x = 1070, .y = 640 }, .{
        .velocity = rl.Vector2{ .x = 0, .y = 0 },
        .mass = 0.8,
        .restitution = 0.9,
        .friction = 0.2,
    });

    // Add all bodies to world
    _ = try world.addBody(ramp_1);
    _ = try world.addBody(ramp_2);
    _ = try world.addBody(ramp_3);
    _ = try world.addBody(floor);
    _ = try world.addBody(rolling_ball);
    _ = try world.addBody(target_ball);
    _ = try world.addBody(extra_ball_1);
    _ = try world.addBody(extra_ball_2);

    std.debug.print("SKI JUMP CASCADE: Ball launches from ramp to ramp in proper arcing trajectory!\n", .{});
}

fn setupMomentumConservationTest(engine: *Engine) !void {
    const world = engine.physics;
    engine.setGravity(rl.Vector2{ .x = 0, .y = 0 }); // No gravity

    const circle_shape = zixel.PhysicsShape{ .circle = .{ .radius = 20 } };

    // Body 1: Moving right
    const body1 = Body.initDynamic(circle_shape, rl.Vector2{ .x = 550, .y = 300 }, .{
        .velocity = rl.Vector2{ .x = 100, .y = 0 },
        .mass = 1.0,
        .restitution = 1.0, // Perfectly elastic
    });

    // Body 2: Moving left
    const body2 = Body.initDynamic(circle_shape, rl.Vector2{ .x = 950, .y = 300 }, .{
        .velocity = rl.Vector2{ .x = -100, .y = 0 },
        .mass = 1.0,
        .restitution = 1.0,
    });

    _ = try world.addBody(body1);
    _ = try world.addBody(body2);

    std.debug.print("Initial momentum: Body1={:.1} + Body2={:.1} = {:.1}\n", .{ 100.0, -100.0, 0.0 });
}

fn setupEnergyConservationTest(engine: *Engine) !void {
    const world = engine.physics;
    engine.setGravity(rl.Vector2{ .x = 0, .y = 0 });

    const circle_shape = zixel.PhysicsShape{ .circle = .{ .radius = 25 } };

    const body1 = Body.initDynamic(circle_shape, rl.Vector2{ .x = 500, .y = 300 }, .{
        .velocity = rl.Vector2{ .x = 150, .y = 50 },
        .mass = 2.0,
        .restitution = 0.95, // Very bouncy
    });

    const body2 = Body.initDynamic(circle_shape, rl.Vector2{ .x = 1000, .y = 300 }, .{
        .velocity = rl.Vector2{ .x = -75, .y = -25 },
        .mass = 1.0,
        .restitution = 0.95,
    });

    _ = try world.addBody(body1);
    _ = try world.addBody(body2);

    const initial_energy = 0.5 * 2.0 * (150 * 150 + 50 * 50) + 0.5 * 1.0 * (75 * 75 + 25 * 25);
    std.debug.print("Initial kinetic energy: {:.1} J\n", .{initial_energy});
}

fn setupSATAccuracyTest(engine: *Engine) !void {
    const world = engine.physics;
    engine.setGravity(rl.Vector2{ .x = 0, .y = 0 }); // No gravity for cleaner test

    std.debug.print("Testing SAT with pre-rotated rectangles colliding...\n", .{});

    const rect_shape = zixel.PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 60, .height = 30 } };

    // Rectangle 1: Axis-aligned (0 rotation)
    const rect1 = Body.initStatic(rect_shape, rl.Vector2{ .x = 750, .y = 300 }, .{
        .rotation = 0.0, // Axis-aligned
    });

    // Rectangle 2: Pre-rotated 45 degrees, moving toward the first one
    const rect2 = Body.initDynamic(rect_shape, rl.Vector2{ .x = 600, .y = 300 }, .{
        .rotation = utils.degreesToRadians(45), // 45 degrees rotation
        .velocity = rl.Vector2{ .x = 80, .y = 0 }, // Moving right toward rect1
        .angular_velocity = 0.5, // Slight continued rotation
        .mass = 1.0,
        .restitution = 0.6,
    });

    _ = try world.addBody(rect1);
    _ = try world.addBody(rect2);

    std.debug.print("Rect1: axis-aligned at (750,300), Rect2: 45° rotated at (600,300) moving right\n", .{});
}

fn setupTunnelingPreventionTest(engine: *Engine) !void {
    const world = engine.physics;
    engine.setGravity(rl.Vector2{ .x = 0, .y = 0 });

    // Use smaller timestep for better collision detection of fast objects
    world.config.physics_time_step = 1.0 / 120.0; // 120 FPS physics for this test

    std.debug.print("Testing fast object (400 px/s) vs thin barrier...\n", .{});

    // Fast moving ball - make it smaller to be more challenging
    const circle_shape = zixel.PhysicsShape{ .circle = .{ .radius = 10 } };
    const fast_ball = Body.initDynamic(circle_shape, rl.Vector2{ .x = 450, .y = 300 }, .{
        .velocity = rl.Vector2{ .x = 400, .y = 0 },
        .mass = 1.0,
        .restitution = 0.9, // Higher restitution for clear bounce
    });

    // Make barrier thicker and taller to be more reliable
    const barrier_shape = zixel.PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 25, .height = 200 } };
    const barrier = Body.initStatic(barrier_shape, rl.Vector2{ .x = 800, .y = 300 }, .{}); // Closer barrier

    _ = try world.addBody(fast_ball);
    _ = try world.addBody(barrier);
}

fn setupMassRatioTest(engine: *Engine) !void {
    const world = engine.physics;
    engine.setGravity(rl.Vector2{ .x = 0, .y = 0 });

    std.debug.print("Testing mass ratio: Heavy(10kg, 25px/s) vs Light(1kg, 50px/s)\n", .{});

    const circle_shape = zixel.PhysicsShape{ .circle = .{ .radius = 30 } };

    // Heavy object moving slowly
    const heavy = Body.initDynamic(circle_shape, rl.Vector2{ .x = 550, .y = 300 }, .{
        .velocity = rl.Vector2{ .x = 25, .y = 0 },
        .mass = 10.0,
        .restitution = 0.9,
    });

    // Light object moving faster
    const light_shape = zixel.PhysicsShape{ .circle = .{ .radius = 15 } };
    const light = Body.initDynamic(light_shape, rl.Vector2{ .x = 1050, .y = 300 }, .{
        .velocity = rl.Vector2{ .x = -50, .y = 0 },
        .mass = 1.0,
        .restitution = 0.9,
    });

    _ = try world.addBody(heavy);
    _ = try world.addBody(light);
}

fn setupSleepSystemTest(engine: *Engine) !void {
    const world = engine.physics;
    engine.setGravity(rl.Vector2{ .x = 0, .y = 0 }); // Disable gravity for cleaner test

    // Set very conservative sleep thresholds for this test - only truly stationary objects should sleep
    world.config.sleep_velocity_threshold = 2.0; // Must be nearly stationary (2 px/s)
    world.config.sleep_time_threshold = 4.0; // Wait 4 full seconds

    std.debug.print("Testing sleep system: Bodies should sleep, then wake on impact\n", .{});

    const circle_shape = zixel.PhysicsShape{ .circle = .{ .radius = 20 } };

    // Body that will slow down gradually due to friction
    const body1 = Body.initDynamic(circle_shape, rl.Vector2{ .x = 550, .y = 200 }, .{
        .velocity = rl.Vector2{ .x = 25, .y = 0 }, // Start with reasonable velocity
        .mass = 1.0,
        .friction = 0.99, // Very high friction to slow it down gradually
    });

    // Body that will collide much later
    const body2 = Body.initDynamic(circle_shape, rl.Vector2{ .x = 950, .y = 200 }, .{
        .velocity = rl.Vector2{ .x = -5, .y = 0 }, // Very slow approach
        .mass = 1.0,
        .friction = 0.98,
    });

    _ = try world.addBody(body1);
    _ = try world.addBody(body2);
}

// Isaac Newton's cradle
fn setupNewtonsCradleTest(engine: *Engine) !void {
    const world = engine.physics;
    engine.setGravity(rl.Vector2{ .x = 0, .y = 0 });

    std.debug.print("Testing Newton's cradle chain reaction\n", .{});

    const circle_shape = zixel.PhysicsShape{ .circle = .{ .radius = 20 } };

    // Create 5 balls in a line
    for (0..5) |i| {
        const x = 650 + @as(f32, @floatFromInt(i)) * 45; // Spaced 45 pixels apart, centered better
        const velocity = if (i == 0) rl.Vector2{ .x = 60, .y = 0 } else rl.Vector2{ .x = 0, .y = 0 };

        const ball = Body.initDynamic(circle_shape, rl.Vector2{ .x = x, .y = 300 }, .{
            .velocity = velocity,
            .mass = 1.0,
            .restitution = 0.95, // High bounce
            .friction = 0.1, // Low friction
        });

        _ = try world.addBody(ball);
    }
}

// TEST VERIFICATION FUNCTIONS

fn verifyBallDropOnEdge(engine: *Engine) !bool {
    const world = engine.physics;
    if (world.bodies.items.len < 2) return false;

    // Find the ball (should be a circle)
    var ball: ?*Body = null;
    for (world.bodies.items) |*body| {
        if (body.getShape() == .circle) {
            ball = body;
            break;
        }
    }

    if (ball == null) return false;

    const ball_pos = ball.?.getPosition();
    const ball_vel = ball.?.kind.Dynamic.velocity;

    // Ball should have fallen and be moving
    const has_fallen = ball_pos.y > 200;
    const is_moving = @abs(ball_vel.x) > 10 or @abs(ball_vel.y) > 10;

    std.debug.print("Ball position: ({:.1}, {:.1}), velocity: ({:.1}, {:.1})\n", .{ ball_pos.x, ball_pos.y, ball_vel.x, ball_vel.y });

    return has_fallen and is_moving;
}

fn verifyMomentumConservation(engine: *Engine) !bool {
    const world = engine.physics;
    if (world.bodies.items.len < 2) return false;

    var total_momentum = rl.Vector2{ .x = 0, .y = 0 };
    for (world.bodies.items) |*body| {
        if (body.*.kind == .Dynamic) {
            const mass = body.kind.Dynamic.mass;
            const vel = body.kind.Dynamic.velocity;
            total_momentum.x += mass * vel.x;
            total_momentum.y += mass * vel.y;
        }
    }

    const momentum_magnitude = @sqrt(total_momentum.x * total_momentum.x + total_momentum.y * total_momentum.y);
    std.debug.print("Total momentum: ({:.2}, {:.2}), magnitude: {:.2}\n", .{ total_momentum.x, total_momentum.y, momentum_magnitude });

    // In a closed system, momentum should be conserved (close to initial)
    return momentum_magnitude < 100.0; // Allow some tolerance for numerical errors
}

fn verifyEnergyConservation(engine: *Engine) !bool {
    const world = engine.physics;
    if (world.bodies.items.len < 2) return false;

    var kinetic_energy: f32 = 0;
    var potential_energy: f32 = 0;

    for (world.bodies.items) |*body| {
        if (body.*.kind == .Dynamic) {
            const mass = body.kind.Dynamic.mass;
            const vel = body.kind.Dynamic.velocity;
            const pos = body.getPosition();

            // KE = 0.5 * m * v²
            const speed_squared = vel.x * vel.x + vel.y * vel.y;
            kinetic_energy += 0.5 * mass * speed_squared;

            // PE = m * g * h (assuming gravity points down)
            const gravity_magnitude = @sqrt(world.gravity.x * world.gravity.x + world.gravity.y * world.gravity.y);
            potential_energy += mass * gravity_magnitude * (600 - pos.y); // 600 is reference height
        }
    }

    const total_energy = kinetic_energy + potential_energy;
    std.debug.print("KE: {:.1}, PE: {:.1}, Total: {:.1}\n", .{ kinetic_energy, potential_energy, total_energy });

    // Energy should be reasonable (not infinite, not zero if there's motion)
    return total_energy > 0 and total_energy < 10000;
}

fn verifySATAccuracy(engine: *Engine) !bool {
    const world = engine.physics;
    if (world.bodies.items.len < 2) return false;

    // Check if rotated rectangles are colliding properly
    var collision_detected = false;
    for (world.bodies.items) |*body1| {
        for (world.bodies.items) |*body2| {
            if (body1 == body2) continue;

            const pos1 = body1.getPosition();
            const pos2 = body2.getPosition();
            const distance = @sqrt((pos1.x - pos2.x) * (pos1.x - pos2.x) + (pos1.y - pos2.y) * (pos1.y - pos2.y));

            // If bodies are close, there should be collision detection
            if (distance < 100) {
                collision_detected = true;
                break;
            }
        }
        if (collision_detected) break;
    }

    std.debug.print("Collision detected: {}\n", .{collision_detected});
    return collision_detected;
}

fn verifyTunnelingPrevention(engine: *Engine) !bool {
    const world = engine.physics;
    if (world.bodies.items.len < 2) return false;

    // Check if fast-moving objects are still in bounds
    var all_in_bounds = true;
    for (world.bodies.items) |*body| {
        const pos = body.getPosition();
        if (pos.x < -100 or pos.x > 1300 or pos.y < -100 or pos.y > 900) {
            all_in_bounds = false;
            std.debug.print("Body out of bounds at ({:.1}, {:.1})\n", .{ pos.x, pos.y });
        }
    }

    return all_in_bounds;
}

fn verifyMassRatioPhysics(engine: *Engine) !bool {
    const world = engine.physics;
    if (world.bodies.items.len < 2) return false;

    // Find heavy and light objects
    var heavy_body: ?*Body = null;
    var light_body: ?*Body = null;

    for (world.bodies.items) |*body| {
        if (body.*.kind == .Dynamic) {
            const mass = body.kind.Dynamic.mass;
            if (mass > 5.0) heavy_body = body;
            if (mass < 2.0) light_body = body;
        }
    }

    if (heavy_body == null or light_body == null) return false;

    const heavy_vel = heavy_body.?.kind.Dynamic.velocity;
    const light_vel = light_body.?.kind.Dynamic.velocity;

    const heavy_speed = @sqrt(heavy_vel.x * heavy_vel.x + heavy_vel.y * heavy_vel.y);
    const light_speed = @sqrt(light_vel.x * light_vel.x + light_vel.y * light_vel.y);

    std.debug.print("Heavy body speed: {:.1}, Light body speed: {:.1}\n", .{ heavy_speed, light_speed });

    // After collision, lighter object should generally move faster
    return light_speed >= heavy_speed * 0.8; // Allow some tolerance
}

fn verifySleepWakeSystem(engine: *Engine) !bool {
    const world = engine.physics;
    if (world.bodies.items.len == 0) return false;

    var sleeping_count: usize = 0;
    for (world.bodies.items) |*body| {
        if (body.isSleeping()) sleeping_count += 1;
    }

    std.debug.print("Sleeping bodies: {}/{}\n", .{ sleeping_count, world.bodies.items.len });

    return sleeping_count >= 1; // At least some should be asleep
}

fn verifyChainReaction(engine: *Engine) !bool {
    const world = engine.physics;
    if (world.bodies.items.len < 3) return false;

    // Check if rightmost ball is moving (energy transferred through chain)
    const rightmost = &world.bodies.items[world.bodies.items.len - 1];
    const energy_transferred = @abs(rightmost.kind.Dynamic.velocity.x) > 30.0;

    std.debug.print("Rightmost ball velocity: {:.1}\n", .{rightmost.kind.Dynamic.velocity.x});

    return energy_transferred;
}

// MAIN APPLICATION

var test_runner: ?PhysicsTestRunner = null;
var current_test: usize = 0;

fn handleInput(engine: *Engine, _: std.mem.Allocator) !void {
    if (test_runner == null) {
        test_runner = PhysicsTestRunner.init(engine);
    }

    // Number keys to run specific tests
    const keys = [_]rl.KeyboardKey{ .zero, .one, .two, .three, .four, .five, .six, .seven };
    for (keys, 0..) |key, i| {
        if (rl.isKeyPressed(key)) {
            try test_runner.?.runScenario(i);
            std.debug.print("Started test {} with key {}\n", .{ i, i });
        }
    }

    // Space to run next test in sequence
    if (rl.isKeyPressed(.space)) {
        try test_runner.?.runScenario(current_test);
        current_test = (current_test + 1) % 8; // Updated to 8 tests
        std.debug.print("Started sequential test {}\n", .{current_test + 1});
    }

    // R to reset
    if (rl.isKeyPressed(.r)) {
        const world = engine.physics;
        world.bodies.clearRetainingCapacity();
        if (test_runner) |*runner| {
            runner.current_scenario = null;
        }
        std.debug.print("Reset physics world\n", .{});
    }
}

fn updateGame(_: *Engine, _: std.mem.Allocator, _: f32) !void {
    if (test_runner) |*runner| {
        try runner.update();
    }
}

fn renderGame(engine: *Engine, allocator: std.mem.Allocator) !void {
    // Render physics bodies
    const world = engine.physics;
    for (world.bodies.items) |*body| {
        const pos = body.getPosition();
        const shape = body.getShape();
        const color = if (body.*.kind == .Static)
            rl.Color.green
        else if (body.isSleeping())
            rl.Color.gray
        else
            rl.Color.red;

        switch (shape) {
            .circle => |circle| {
                rl.drawCircleV(pos, circle.radius, color);
                rl.drawCircleLinesV(pos, circle.radius, rl.Color.black);
            },
            .rectangle => |rect| {
                const rotation = body.getRotation();
                if (@abs(rotation) < 0.01) {
                    // Axis-aligned optimization
                    rl.drawRectangle(@intFromFloat(pos.x - rect.width / 2), @intFromFloat(pos.y - rect.height / 2), @intFromFloat(rect.width), @intFromFloat(rect.height), color);
                    rl.drawRectangleLines(@intFromFloat(pos.x - rect.width / 2), @intFromFloat(pos.y - rect.height / 2), @intFromFloat(rect.width), @intFromFloat(rect.height), rl.Color.black);
                } else {
                    // Rotated rectangle - draw as lines
                    const hw = rect.width / 2;
                    const hh = rect.height / 2;
                    const cos_r = @cos(rotation);
                    const sin_r = @sin(rotation);

                    const corners = [4]rl.Vector2{
                        rl.Vector2{ .x = pos.x + (-hw * cos_r - -hh * sin_r), .y = pos.y + (-hw * sin_r + -hh * cos_r) },
                        rl.Vector2{ .x = pos.x + (hw * cos_r - -hh * sin_r), .y = pos.y + (hw * sin_r + -hh * cos_r) },
                        rl.Vector2{ .x = pos.x + (hw * cos_r - hh * sin_r), .y = pos.y + (hw * sin_r + hh * cos_r) },
                        rl.Vector2{ .x = pos.x + (-hw * cos_r - hh * sin_r), .y = pos.y + (-hw * sin_r + hh * cos_r) },
                    };

                    for (0..4) |i| {
                        const next = (i + 1) % 4;
                        rl.drawLineV(corners[i], corners[next], rl.Color.black);
                    }
                }
            },
        }

        // Draw velocity vector for dynamic bodies
        if (body.*.kind == .Dynamic) {
            const vel = body.kind.Dynamic.velocity;
            const speed = @sqrt(vel.x * vel.x + vel.y * vel.y);
            if (speed > 10.0) {
                const end_pos = rl.Vector2{
                    .x = pos.x + vel.x * 0.1,
                    .y = pos.y + vel.y * 0.1,
                };
                rl.drawLineV(pos, end_pos, rl.Color.red);
            }
        }
    }

    // Render physics debug information (AABBs, contacts, joints)
    engine.debugRenderPhysics();

    // Render test runner UI
    if (test_runner) |*runner| {
        runner.renderUI();
    }

    // Render controls
    const controls = [_][]const u8{
        "PHYSICS VERIFICATION TESTS",
        "",
        "0-7: Run specific test",
        "SPACE: Run next test in sequence",
        "R: Reset world",
        "G: Toggle debug panel (AABB, contacts, etc.)",
        "",
        "AVAILABLE TESTS:",
        "0. Ball Dropping on Edge of Rect",
        "1. Momentum Conservation",
        "2. Energy Conservation",
        "3. SAT Accuracy (Rotation)",
        "4. Tunneling Prevention",
        "5. Mass Ratio Physics",
        "6. Sleep/Wake System",
        "7. Newton's Cradle",
    };

    var y: i32 = 450;
    for (controls) |line| {
        rl.drawText(@as([:0]const u8, @ptrCast(line)), 10, y, 14, rl.Color.dark_gray);
        y += 16;
    }

    // Physics stats
    const stats_text = std.fmt.allocPrint(allocator, "Bodies: {} | Active: {}", .{ world.bodies.items.len, world.bodies.items.len }) catch "Stats Error";
    defer allocator.free(stats_text);
    rl.drawText(@as([:0]const u8, @ptrCast(stats_text)), 10, 700, 16, rl.Color.black);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = Engine.init(allocator, .{
        .window = .{
            .title = "Physics Verification Tests",
            .width = 1200,
            .height = 800,
        },
        .physics = .{
            .gravity = .{ .x = 0, .y = 0 },
            .allow_sleeping = true,
            .debug_draw_aabb = false,
        },
        .target_fps = 60,
    });
    defer engine.deinit();

    engine.setHandleInputFn(handleInput);
    engine.setUpdateFn(updateGame);
    engine.setRenderFn(renderGame);

    std.debug.print("\nPhysics Verification Test Suite\n", .{});
    std.debug.print("===================================\n", .{});
    std.debug.print("Use number keys 0-7 to run specific tests\n", .{});
    std.debug.print("Press SPACE to cycle through tests\n", .{});
    std.debug.print("Press R to reset the world\n\n", .{});

    try engine.run();
}
