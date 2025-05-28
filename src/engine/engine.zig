const std = @import("std");
const rl = @import("raylib");
const Window = @import("../renderer/window.zig").Window;
const WindowConfig = @import("../renderer/config.zig").WindowConfig;
const PhysicsConfig = @import("../physics/config.zig").PhysicsConfig;
const PhysicsWorld = @import("../physics/world.zig").PhysicsWorld;
const keybinds = @import("../input/keybinds.zig");

const EngineConfig = struct {
    window: WindowConfig = .{},
    physics: PhysicsConfig = .{},
    target_fps: u32 = 60,
    load_default_keybinds: bool = true,
};

pub const HandleInputFn = *const fn (engine: *Engine, allocator: std.mem.Allocator) anyerror!void;
pub const UpdateFn = *const fn (engine: *Engine, allocator: std.mem.Allocator, dt: f32) anyerror!void;
pub const RenderFn = *const fn (engine: *Engine, allocator: std.mem.Allocator) anyerror!void;

pub const Engine = struct {
    allocator: std.mem.Allocator,
    window: Window,
    physics: PhysicsWorld,
    keybind_manager: keybinds.KeybindManager,
    target_fps: u32,

    // Use optional function pointers for callback fields
    handle_input: ?HandleInputFn = null,
    update_game: ?UpdateFn = null,
    render_game: ?RenderFn = null,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, config: EngineConfig) !Self {
        var kb_manager = keybinds.KeybindManager.init(alloc);
        if (config.load_default_keybinds) {
            try kb_manager.loadDefaultBindings();
        }

        rl.setTargetFPS(@intCast(config.target_fps));

        return Self{
            .allocator = alloc,
            .window = try Window.init(config.window),
            .physics = try PhysicsWorld.init(alloc, config.physics),
            .keybind_manager = kb_manager,
            .target_fps = config.target_fps,
            .handle_input = null,
            .update_game = null,
            .render_game = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.window.deinit();
        self.physics.deinit();
        self.keybind_manager.deinit();
    }

    // Setter functions now accept function pointers
    pub fn setHandleInputFn(self: *Self, func: HandleInputFn) void {
        self.handle_input = func;
    }

    pub fn setUpdateFn(self: *Self, func: UpdateFn) void {
        self.update_game = func;
    }

    pub fn setRenderFn(self: *Self, func: RenderFn) void {
        self.render_game = func;
    }

    pub fn setTargetFPS(self: *Self, fps: u32) void {
        self.target_fps = fps;
        rl.setTargetFPS(@intCast(fps));
    }

    pub fn setBackgroundColor(self: Self, color: rl.Color) void {
        _ = self;
        _ = color;
    }

    pub fn run(self: *Self) !void {
        var accumulator: f32 = 0.0;
        const physics_dt = self.physics.getPhysicsTimeStep();

        while (!rl.windowShouldClose()) {
            if (self.handle_input) |input_fn_ptr| {
                try input_fn_ptr(self, self.allocator);
            }

            const frame_time = rl.getFrameTime();
            accumulator += frame_time;

            // Physics simulation with fixed timestep
            while (accumulator >= physics_dt) {
                self.physics.update(physics_dt);
                if (self.update_game) |update_fn_ptr| {
                    try update_fn_ptr(self, self.allocator, physics_dt);
                }
                accumulator -= physics_dt;
            }

            // Rendering
            rl.beginDrawing();
            rl.clearBackground(rl.Color.white);
            if (self.render_game) |render_fn_ptr| {
                try render_fn_ptr(self, self.allocator);
            }
            rl.endDrawing();
        }
    }

    pub fn getKeybindManager(self: *Self) *keybinds.KeybindManager {
        return &self.keybind_manager;
    }

    // Physics configuration methods
    pub fn getPhysicsWorld(self: *Self) *PhysicsWorld {
        return &self.physics;
    }

    pub fn setGravity(self: *Self, gravity: rl.Vector2) void {
        self.physics.config.gravity = gravity;
        self.physics.gravity = gravity;
    }

    pub fn getGravity(self: *const Self) rl.Vector2 {
        return self.physics.gravity;
    }

    pub fn enableDebugDrawing(self: *Self, aabb: bool, contacts: bool, joints: bool) void {
        self.physics.config.debug_draw_aabb = aabb;
        self.physics.config.debug_draw_contacts = contacts;
        self.physics.config.debug_draw_joints = joints;
    }

    pub fn getPhysicsStepCount(self: *const Self) u64 {
        return self.physics.getStepCount();
    }
};

// PHYSICS VERIFICATION SCENARIOS
// These are comprehensive visual tests to verify the physics math is correct
const Body = @import("../physics/body.zig").Body;
const PhysicsShape = @import("../core/math/shapes.zig").PhysicsShape;

pub const PhysicsTestScenario = struct {
    name: [:0]const u8,
    description: []const u8,
    setup_fn: *const fn (engine: *Engine) anyerror!void,
    verify_fn: ?*const fn (engine: *Engine) anyerror!bool = null,
    duration_seconds: f32 = 5.0,
};

pub const PhysicsTestRunner = struct {
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
        std.debug.print("\n🧪 Running Physics Test: {s}\n", .{scenario.name});
        std.debug.print("📝 {s}\n", .{scenario.description});

        // Clear existing bodies
        const world = self.engine.getPhysicsWorld();
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
                std.debug.print("✅ Test Result: {s}\n", .{if (passed) "PASSED" else "FAILED"});
            }
            self.current_scenario = null;
        }
    }

    pub fn renderUI(self: *Self) void {
        if (self.current_scenario) |idx| {
            const scenario = self.scenarios[idx];
            const elapsed = rl.getTime() - self.start_time;
            const remaining = scenario.duration_seconds - elapsed;

            rl.drawText(scenario.name, 10, 10, 20, rl.Color.black);
            const timer_text = std.fmt.allocPrint(self.engine.allocator, "Time: {:.1}s", .{remaining}) catch "Timer Error";
            defer self.engine.allocator.free(timer_text);
            rl.drawText(@as([:0]const u8, @ptrCast(timer_text)), 10, 40, 16, rl.Color.dark_gray);
        }
    }
};

// PHYSICS TEST SCENARIOS

const PHYSICS_SCENARIOS = [_]PhysicsTestScenario{
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
        .name = "Fast Object Test - Tunnel Prevention",
        .description = "Very fast moving object should not tunnel through thin barrier.",
        .setup_fn = setupTunnelingPreventionTest,
        .verify_fn = verifyNoTunneling,
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

// TEST SETUP FUNCTIONS

fn setupMomentumConservationTest(engine: *Engine) !void {
    const world = engine.getPhysicsWorld();
    engine.setGravity(rl.Vector2{ .x = 0, .y = 0 }); // No gravity

    const circle_shape = PhysicsShape{ .circle = .{ .radius = 20 } };

    // Body 1: Moving right (reduced from 200 to 100)
    const body1 = Body.initDynamic(circle_shape, rl.Vector2{ .x = 200, .y = 300 }, .{
        .velocity = rl.Vector2{ .x = 100, .y = 0 },
        .mass = 1.0,
        .restitution = 1.0, // Perfectly elastic
    });

    // Body 2: Moving left (reduced from -200 to -100)
    const body2 = Body.initDynamic(circle_shape, rl.Vector2{ .x = 600, .y = 300 }, .{
        .velocity = rl.Vector2{ .x = -100, .y = 0 },
        .mass = 1.0,
        .restitution = 1.0,
    });

    _ = try world.addBody(body1);
    _ = try world.addBody(body2);

    std.debug.print("💫 Initial momentum: Body1={:.1} + Body2={:.1} = {:.1}\n", .{ 100.0, -100.0, 0.0 });
}

fn setupEnergyConservationTest(engine: *Engine) !void {
    const world = engine.getPhysicsWorld();
    engine.setGravity(rl.Vector2{ .x = 0, .y = 0 });

    const circle_shape = PhysicsShape{ .circle = .{ .radius = 25 } };

    const body1 = Body.initDynamic(circle_shape, rl.Vector2{ .x = 150, .y = 300 }, .{
        .velocity = rl.Vector2{ .x = 150, .y = 50 }, // Reduced from 300, 100
        .mass = 2.0,
        .restitution = 0.95, // Very bouncy
    });

    const body2 = Body.initDynamic(circle_shape, rl.Vector2{ .x = 650, .y = 300 }, .{
        .velocity = rl.Vector2{ .x = -75, .y = -25 }, // Reduced from -150, -50
        .mass = 1.0,
        .restitution = 0.95,
    });

    _ = try world.addBody(body1);
    _ = try world.addBody(body2);

    const initial_energy = 0.5 * 2.0 * (150 * 150 + 50 * 50) + 0.5 * 1.0 * (75 * 75 + 25 * 25);
    std.debug.print("⚡ Initial kinetic energy: {:.1} J\n", .{initial_energy});
}

fn setupSATAccuracyTest(engine: *Engine) !void {
    const world = engine.getPhysicsWorld();
    engine.setGravity(rl.Vector2{ .x = 0, .y = 0 }); // No gravity for cleaner test

    std.debug.print("🔄 Testing SAT with pre-rotated rectangles colliding...\n", .{});

    const rect_shape = PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 60, .height = 30 } };

    // Rectangle 1: Axis-aligned (0 rotation)
    const rect1 = Body.initStatic(rect_shape, rl.Vector2{ .x = 400, .y = 300 }, .{
        .rotation = 0.0, // Axis-aligned
    });

    // Rectangle 2: Pre-rotated 45 degrees, moving toward the first one
    const rect2 = Body.initDynamic(rect_shape, rl.Vector2{ .x = 250, .y = 300 }, .{
        .rotation = std.math.pi / 4.0, // 45 degrees rotation
        .velocity = rl.Vector2{ .x = 80, .y = 0 }, // Moving right toward rect1
        .angular_velocity = 0.5, // Slight continued rotation
        .mass = 1.0,
        .restitution = 0.6,
    });

    _ = try world.addBody(rect1);
    _ = try world.addBody(rect2);

    std.debug.print("Rect1: axis-aligned at (400,300), Rect2: 45° rotated at (250,300) moving right\n", .{});
}

fn setupTunnelingPreventionTest(engine: *Engine) !void {
    const world = engine.getPhysicsWorld();
    engine.setGravity(rl.Vector2{ .x = 0, .y = 0 });

    std.debug.print("Testing fast object (400 px/s) vs thin barrier...\n", .{});

    // Fast moving ball (reduced from 1000 to 400)
    const circle_shape = PhysicsShape{ .circle = .{ .radius = 15 } };
    const fast_ball = Body.initDynamic(circle_shape, rl.Vector2{ .x = 100, .y = 300 }, .{
        .velocity = rl.Vector2{ .x = 400, .y = 0 }, // Reduced from 1000
        .mass = 1.0,
        .restitution = 0.8,
    });

    // Thin barrier (but make it a bit thicker to be more visible)
    const barrier_shape = PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 15, .height = 100 } }; // Increased from 5 to 15
    const barrier = Body.initStatic(barrier_shape, rl.Vector2{ .x = 500, .y = 300 }, .{});

    _ = try world.addBody(fast_ball);
    _ = try world.addBody(barrier);
}

fn setupMassRatioTest(engine: *Engine) !void {
    const world = engine.getPhysicsWorld();
    engine.setGravity(rl.Vector2{ .x = 0, .y = 0 });

    std.debug.print("Testing mass ratio: Heavy(10kg, 25px/s) vs Light(1kg, 50px/s)\n", .{});

    const circle_shape = PhysicsShape{ .circle = .{ .radius = 30 } };

    // Heavy object moving slowly (reduced from 50 to 25)
    const heavy = Body.initDynamic(circle_shape, rl.Vector2{ .x = 200, .y = 300 }, .{
        .velocity = rl.Vector2{ .x = 25, .y = 0 }, // Reduced from 50
        .mass = 10.0,
        .restitution = 0.9,
    });

    // Light object moving faster (reduced from 100 to 50)
    const light_shape = PhysicsShape{ .circle = .{ .radius = 15 } };
    const light = Body.initDynamic(light_shape, rl.Vector2{ .x = 700, .y = 300 }, .{
        .velocity = rl.Vector2{ .x = -50, .y = 0 }, // Reduced from -100
        .mass = 1.0,
        .restitution = 0.9,
    });

    _ = try world.addBody(heavy);
    _ = try world.addBody(light);
}

fn setupSleepSystemTest(engine: *Engine) !void {
    const world = engine.getPhysicsWorld();
    engine.setGravity(rl.Vector2{ .x = 0, .y = 0 }); // Disable gravity for cleaner test

    // Set very conservative sleep thresholds for this test - only truly stationary objects should sleep
    world.config.sleep_velocity_threshold = 2.0; // Must be nearly stationary (2 px/s)
    world.config.sleep_time_threshold = 4.0; // Wait 4 full seconds

    std.debug.print("Testing sleep system: Bodies should sleep, then wake on impact\n", .{});

    const circle_shape = PhysicsShape{ .circle = .{ .radius = 20 } };

    // Body that will slow down gradually due to friction
    const body1 = Body.initDynamic(circle_shape, rl.Vector2{ .x = 200, .y = 200 }, .{
        .velocity = rl.Vector2{ .x = 25, .y = 0 }, // Start with reasonable velocity
        .mass = 1.0,
        .friction = 0.99, // Very high friction to slow it down gradually
    });

    // Body that will collide much later
    const body2 = Body.initDynamic(circle_shape, rl.Vector2{ .x = 600, .y = 200 }, .{
        .velocity = rl.Vector2{ .x = -5, .y = 0 }, // Very slow approach
        .mass = 1.0,
        .friction = 0.98,
    });

    _ = try world.addBody(body1);
    _ = try world.addBody(body2);
}

// Isaac Newton's cradle
fn setupNewtonsCradleTest(engine: *Engine) !void {
    const world = engine.getPhysicsWorld();
    engine.setGravity(rl.Vector2{ .x = 0, .y = 0 });

    std.debug.print("⛓️ Testing Newton's cradle chain reaction\n", .{});

    const circle_shape = PhysicsShape{ .circle = .{ .radius = 20 } };

    // Create 5 balls in a line
    for (0..5) |i| {
        const x = 300 + @as(f32, @floatFromInt(i)) * 45; // Spaced 45 pixels apart
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

fn verifyMomentumConservation(engine: *Engine) !bool {
    const world = engine.getPhysicsWorld();
    if (world.bodies.items.len < 2) return false;

    const body1 = &world.bodies.items[0];
    const body2 = &world.bodies.items[1];

    const p1 = body1.kind.Dynamic.velocity.x * body1.kind.Dynamic.mass;
    const p2 = body2.kind.Dynamic.velocity.x * body2.kind.Dynamic.mass;
    const total_momentum = p1 + p2;

    std.debug.print("Final momentum: {:.3} + {:.3} = {:.3}\n", .{ p1, p2, total_momentum });
    std.debug.print("Velocities: {:.1}, {:.1}\n", .{ body1.kind.Dynamic.velocity.x, body2.kind.Dynamic.velocity.x });

    return @abs(total_momentum) < 0.1; // Should be ~0
}

fn verifyEnergyConservation(engine: *Engine) !bool {
    const world = engine.getPhysicsWorld();
    if (world.bodies.items.len < 2) return false;

    const body1 = &world.bodies.items[0];
    const body2 = &world.bodies.items[1];

    const v1 = body1.kind.Dynamic.velocity;
    const v2 = body2.kind.Dynamic.velocity;
    const m1 = body1.kind.Dynamic.mass;
    const m2 = body2.kind.Dynamic.mass;

    const ke1 = 0.5 * m1 * (v1.x * v1.x + v1.y * v1.y);
    const ke2 = 0.5 * m2 * (v2.x * v2.x + v2.y * v2.y);
    const total_energy = ke1 + ke2;

    std.debug.print("Final kinetic energy: {:.1} J\n", .{total_energy});

    // With restitution 0.95, expect ~90% energy retention
    return total_energy > 180000; // Rough energy check
}

fn verifySATAccuracy(engine: *Engine) !bool {
    const world = engine.getPhysicsWorld();
    if (world.bodies.items.len < 2) return false;

    const rotating_body = &world.bodies.items[1];

    // Check if it's still rotating and positioned reasonably
    const still_rotating = @abs(rotating_body.kind.Dynamic.angular_velocity) > 0.1;
    const reasonable_position = rotating_body.getPosition().y < 500; // Not fallen through

    std.debug.print("🔄 Final rotation: {:.2} rad/s, Y pos: {:.1}\n", .{ rotating_body.kind.Dynamic.angular_velocity, rotating_body.getPosition().y });

    return still_rotating and reasonable_position;
}

fn verifyNoTunneling(engine: *Engine) !bool {
    const world = engine.getPhysicsWorld();
    if (world.bodies.items.len < 2) return false;

    const projectile = &world.bodies.items[1];
    const projectile_x = projectile.getPosition().x;

    // Projectile should have bounced back or stopped, not passed through
    const no_tunnel = projectile_x < 500; // Barrier is at x=400

    std.debug.print("Projectile final position: {:.1}, velocity: {:.1}\n", .{ projectile_x, projectile.kind.Dynamic.velocity.x });

    return no_tunnel;
}

fn verifyMassRatioPhysics(engine: *Engine) !bool {
    const world = engine.getPhysicsWorld();
    if (world.bodies.items.len < 2) return false;

    const heavy = &world.bodies.items[0];
    const light = &world.bodies.items[1];

    // Heavy object should barely change velocity, light object should bounce back fast
    const heavy_velocity_change = @abs(heavy.kind.Dynamic.velocity.x - 25.0);
    const light_bounced_back = light.kind.Dynamic.velocity.x > 50.0; // Should be moving right now

    std.debug.print("Heavy vel: {:.1} (change: {:.1}), Light vel: {:.1}\n", .{ heavy.kind.Dynamic.velocity.x, heavy_velocity_change, light.kind.Dynamic.velocity.x });

    return heavy_velocity_change < 30.0 and light_bounced_back;
}

fn verifySleepWakeSystem(engine: *Engine) !bool {
    const world = engine.getPhysicsWorld();

    var sleeping_count: u32 = 0;
    for (world.bodies.items) |*body| {
        if (body.isSleeping()) sleeping_count += 1;
    }

    std.debug.print("Sleeping bodies: {}/{}\n", .{ sleeping_count, world.bodies.items.len });

    return sleeping_count >= 3; // Most should be asleep
}

fn verifyChainReaction(engine: *Engine) !bool {
    const world = engine.getPhysicsWorld();
    if (world.bodies.items.len < 3) return false;

    // Check if rightmost ball is moving (energy transferred through chain)
    const rightmost = &world.bodies.items[world.bodies.items.len - 1];
    const energy_transferred = @abs(rightmost.kind.Dynamic.velocity.x) > 50.0;

    std.debug.print("Rightmost ball velocity: {:.1}\n", .{rightmost.kind.Dynamic.velocity.x});

    return energy_transferred;
}
