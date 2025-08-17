const std = @import("std");
const rl = @import("raylib");
const Allocator = std.mem.Allocator;
const Body = @import("body.zig").Body;
const Vector2 = rl.Vector2;
const collision = @import("collision.zig");
const checkBodiesCollision = collision.checkBodiesCollision;
const resolveCollision = collision.resolveCollision;
const correctPositions = collision.correctPositions;
const ContactManifold = collision.ContactManifold;
const CollisionResponse = @import("response.zig").CollisionResponse;
const Engine = @import("../engine/engine.zig").Engine;

const logging = @import("../core/logging.zig");

pub const PhysicsConfig = struct {
    // World settings
    gravity: Vector2 = Vector2{ .x = 0, .y = 9.81 },

    // Solver settings
    position_iterations: u32 = 3, // Number of position correction iterations
    velocity_iterations: u32 = 8, // Number of velocity solver iterations

    // Timestep settings
    physics_time_step: f32 = 1.0 / 60.0, // Fixed physics timestep (60 FPS)
    max_delta_time: f32 = 1.0 / 30.0, // Maximum allowed delta time to prevent spiral of death

    // Collision settings
    allow_sleeping: bool = true, // Allow bodies to go to sleep when inactive
    sleep_time_threshold: f32 = 5.0, // Time before a body can sleep (seconds)
    sleep_velocity_threshold: f32 = 15.0, // Velocity threshold for sleeping

    // Contact settings
    contact_slop: f32 = 0.005, // Allowed penetration before position correction
    baumgarte_factor: f32 = 0.2, // Position correction factor (0-1)

    // Performance settings
    enable_warm_starting: bool = true, // Reuse impulses from previous frame
    enable_continuous_physics: bool = false, // Continuous collision detection (expensive)

    // Debug settings
    debug_draw_aabb: bool = false,
    debug_draw_contacts: bool = false,
    debug_draw_joints: bool = false,

    // New field
    restitution_clamp_threshold: f32 = 15.0, // Velocity threshold to kill bounce and prevent jitter
};

pub const PhysicsWorld = struct {
    allocator: std.mem.Allocator,
    bodies: std.ArrayList(*Body),
    config: PhysicsConfig,
    next_id: usize = 0,
    gravity: Vector2,

    // Simulation state
    accumulated_time: f32 = 0.0,
    step_count: u64 = 0,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, config: PhysicsConfig) Self {
        return Self{
            .allocator = alloc,
            .bodies = std.ArrayList(*Body).init(alloc),
            .config = config,
            .gravity = config.gravity,
        };
    }

    pub fn deinit(self: *Self) void {
        // Destroy all allocated bodies before deinitializing the list
        for (self.bodies.items) |body| {
            self.allocator.destroy(body);
        }
        self.bodies.deinit();
    }

    pub fn update(self: *Self, engine: *Engine, deltaTime: f32) void {
        // Clamp delta time to prevent spiral of death
        const clamped_dt = @min(deltaTime, self.config.max_delta_time);
        self.accumulated_time += clamped_dt;

        // Fixed timestep physics simulation
        while (self.accumulated_time >= self.config.physics_time_step) {
            self.stepPhysics(engine, self.config.physics_time_step);
            self.accumulated_time -= self.config.physics_time_step;
            self.step_count += 1;
        }
    }

    fn stepPhysics(self: *Self, engine: *Engine, dt: f32) void {
        // Handle sleeping bodies FIRST - before physics changes velocities
        if (self.config.allow_sleeping) {
            self.updateSleepingBodies(dt);
        }

        // Apply gravity and integrate forces (but NOT position yet)
        for (self.bodies.items) |body| {
            if (body.kind == .dynamic and !body.isSleeping()) {
                // Apply gravity
                const gravity_force = Vector2{
                    .x = self.config.gravity.x * body.kind.dynamic.mass,
                    .y = self.config.gravity.y * body.kind.dynamic.mass,
                };
                body.applyForce(gravity_force);

                // Only update velocity from forces, NOT position yet
                const dyn_body = &body.kind.dynamic;
                dyn_body.velocity = dyn_body.velocity.add(dyn_body.acceleration.scale(dt));
                dyn_body.acceleration = Vector2{ .x = 0.0, .y = 0.0 };
            }
        }

        // Collision detection and response BEFORE position integration
        self.detectAndResolveCollisions(engine);

        // Position integration AFTER collision response
        for (self.bodies.items) |body| {
            if (body.kind == .dynamic and !body.isSleeping()) {
                const dyn_body = &body.kind.dynamic;
                dyn_body.position = dyn_body.position.add(dyn_body.velocity.scale(dt));
            } else if (body.kind == .kinematic) {
                // Kinematic bodies also need to be updated to move
                body.update(dt);
            }
        }
    }

    fn detectAndResolveCollisions(self: *Self, engine: *Engine) void {
        var i: usize = 0;
        while (i < self.bodies.items.len) : (i += 1) {
            var body1_ptr = self.bodies.items[i];

            var j: usize = i + 1;
            while (j < self.bodies.items.len) : (j += 1) {
                var body2_ptr = self.bodies.items[j];

                // Skip collision between two static bodies
                if (body1_ptr.kind != .dynamic and body2_ptr.kind != .dynamic) {
                    continue;
                }

                // Skip collision between two sleeping bodies
                if (body1_ptr.isSleeping() and body2_ptr.isSleeping()) {
                    continue;
                }

                // Broadphase: AABB collision
                const aabb1 = body1_ptr.aabb();
                const aabb2 = body2_ptr.aabb();

                if (aabb1.intersects(aabb2)) {
                    // Narrowphase: Detailed collision detection
                    if (checkBodiesCollision(body1_ptr, body2_ptr)) |manifold| {
                        // --- FIX: Wake-up logic refinement ---
                        const body1_is_active = !body1_ptr.isSleeping() and body1_ptr.kind == .dynamic;
                        const body2_is_active = !body2_ptr.isSleeping() and body2_ptr.kind == .dynamic;

                        // Only process wake-up logic if there's a reason to
                        if (body1_is_active or body2_is_active) {
                            const vel1 = body1_ptr.getVelocity();
                            const vel2 = body2_ptr.getVelocity();
                            const rel_vel = Vector2{ .x = vel2.x - vel1.x, .y = vel2.y - vel1.y };
                            const vel_along_normal = rel_vel.x * manifold.normal.x + rel_vel.y * manifold.normal.y;

                            // Wake up bodies if the impact is significant enough
                            if (vel_along_normal < -self.config.sleep_velocity_threshold) {
                                if (!body1_is_active) body1_ptr.wakeUp();
                                if (!body2_is_active) body2_ptr.wakeUp();
                            }
                        }

                        // Calculate combined restitution and friction using both bodies' properties
                        const restitution1 = body1_ptr.getRestitution();
                        const restitution2 = body2_ptr.getRestitution();
                        const friction1 = body1_ptr.getFriction();
                        const friction2 = body2_ptr.getFriction();

                        // Resolve collision with combined material properties (includes friction)
                        CollisionResponse.resolveCollisionWithMaterials(body1_ptr, body2_ptr, manifold, restitution1, restitution2, friction1, friction2, self.config.restitution_clamp_threshold);

                        // Position correction to reduce penetration
                        if (manifold.penetration > self.config.contact_slop) {
                            CollisionResponse.correctPositions(body1_ptr, body2_ptr, manifold, self.config.baumgarte_factor);
                        }

                        // Call scene-specific collision callback if available
                        if (engine.current_scene) |scene| {
                            if (scene.collision_callback) |callback| {
                                callback(scene.context, body1_ptr, body2_ptr) catch |err| {
                                    logging.general.err("Error in collision callback: {}\n", .{err});
                                };
                            }
                        }
                    }
                }
            }
        }
    }

    fn updateSleepingBodies(self: *Self, dt: f32) void {
        for (self.bodies.items) |body| {
            if (body.kind == .dynamic and !body.isSleeping()) {
                const dyn_body = &body.kind.dynamic;
                const velocity_mag = @sqrt(dyn_body.velocity.x * dyn_body.velocity.x +
                    dyn_body.velocity.y * dyn_body.velocity.y);
                const angular_velocity_mag = @abs(dyn_body.angular_velocity);

                if (velocity_mag < self.config.sleep_velocity_threshold and
                    angular_velocity_mag < self.config.sleep_velocity_threshold)
                {
                    // Body is slow enough to potentially sleep
                    dyn_body.sleep_time += dt;
                    if (dyn_body.sleep_time > self.config.sleep_time_threshold) {
                        body.putToSleep();
                    }
                } else {
                    // Body is moving too fast, reset sleep timer
                    dyn_body.sleep_time = 0.0;
                }
            }
        }
    }

    pub fn attach(self: *Self, b: *Body) !void {
        try self.bodies.append(b);
    }

    pub fn detach(self: *Self, b: *Body) void {
        for (self.bodies.items, 0..) |body, i| {
            if (body == b) {
                _ = self.bodies.swapRemove(i);
                return;
            }
        }
    }

    pub fn has(self: *Self, b: *Body) bool {
        for (self.bodies.items) |body| {
            if (body == b) return true;
        }
        return false;
    }

    // Legacy compatibility methods
    pub fn addBody(self: *Self, body: Body) !usize {
        const body_ptr = try self.allocator.create(Body);
        body_ptr.* = body;
        body_ptr.id = self.next_id;
        self.next_id += 1;
        try self.bodies.append(body_ptr);
        return body_ptr.id;
    }

    pub fn getBodyById(self: *Self, id: usize) ?*Body {
        for (self.bodies.items) |body| {
            if (body.id == id) return body;
        }
        return null;
    }

    // Helper to get body by pointer for old interface
    pub fn getBody(self: *Self, id: usize) ?*Body {
        return self.getBodyById(id);
    }

    pub fn removeBody(self: *Self, index: usize) void {
        // For legacy compatibility, find by index in array
        if (index < self.bodies.items.len) {
            const body = self.bodies.items[index];
            self.allocator.destroy(body);
            _ = self.bodies.swapRemove(index);
        }
    }

    pub fn getBodyCount(self: *Self) usize {
        return self.bodies.items.len;
    }

    /// Debug rendering - call this in the render loop to draw debug information
    pub fn debugRender(self: *Self) void {
        if (self.config.debug_draw_aabb) {
            self.renderAABBs();
        }

        if (self.config.debug_draw_contacts) {
            self.renderContactPoints();
        }

        if (self.config.debug_draw_joints) {
            self.renderJoints();
        }
    }

    /// Render AABBs (bounding boxes) for all bodies
    fn renderAABBs(self: *Self) void {
        for (self.bodies.items) |body| {
            const aabb = body.aabb();
            const width = aabb.max.x - aabb.min.x;
            const height = aabb.max.y - aabb.min.y;

            const aabb_rect = rl.Rectangle{
                .x = aabb.min.x,
                .y = aabb.min.y,
                .width = width,
                .height = height,
            };
            rl.drawRectangleLinesEx(aabb_rect, 2.0, rl.Color.orange);
        }
    }

    /// Render contact points from collisions this frame
    fn renderContactPoints(self: *Self) void {
        // We need to store contact points from the collision detection
        // For now, let's re-detect collisions just for rendering
        var i: usize = 0;
        while (i < self.bodies.items.len) : (i += 1) {
            var body1_ptr = self.bodies.items[i];

            var j: usize = i + 1;
            while (j < self.bodies.items.len) : (j += 1) {
                var body2_ptr = self.bodies.items[j];

                // Skip collision between two static bodies
                if (body1_ptr.kind != .dynamic and body2_ptr.kind != .dynamic) {
                    continue;
                }

                // Broadphase: AABB collision
                const aabb1 = body1_ptr.aabb();
                const aabb2 = body2_ptr.aabb();

                if (aabb1.intersects(aabb2)) {
                    // Narrowphase: Check for actual collision
                    if (checkBodiesCollision(body1_ptr, body2_ptr)) |manifold| {
                        // Draw contact point
                        rl.drawCircleV(manifold.point, 3.0, rl.Color.red);

                        // Draw contact normal
                        const normal_end = Vector2{
                            .x = manifold.point.x + manifold.normal.x * 20.0,
                            .y = manifold.point.y + manifold.normal.y * 20.0,
                        };
                        rl.drawLineV(manifold.point, normal_end, rl.Color.orange);

                        // Draw penetration depth indicator
                        const penetration_text = std.fmt.allocPrintZ(std.heap.page_allocator, "{d:.2}", .{manifold.penetration}) catch "?";
                        defer std.heap.page_allocator.free(penetration_text);
                        rl.drawText(@ptrCast(penetration_text), @intFromFloat(manifold.point.x + 5), @intFromFloat(manifold.point.y - 10), 12, rl.Color.white);
                    }
                }
            }
        }
    }

    /// Render joints (placeholder for when joint system is implemented)
    fn renderJoints(self: *Self) void {
        // Joints not implemented yet, but when they are, this would draw:
        // - Joint anchor points
        // - Joint limits/constraints
        // - Joint forces/torques
        _ = self;
    }
};

/// Test code for AABB collision detection
const testing = @import("std").testing;
const core_math = @import("../math/aabb.zig"); // For AABB
const physics_body = @import("body.zig"); // For Body, StaticBodyOptions etc.
const physics_shapes = @import("../math/shapes.zig"); // For PhysicsShape

// Helper to create a static body for tests
fn createTestStaticBody(shape: physics_shapes.PhysicsShape, pos: rl.Vector2, rot_rad: f32) physics_body.Body {
    return physics_body.Body.initStatic(shape, pos, .{ .rotation = rot_rad });
}

// Helper to create a dynamic body for tests (can be adapted if needed)
fn createTestDynamicBody(shape: physics_shapes.PhysicsShape, pos: rl.Vector2, rot_rad: f32) physics_body.Body {
    return physics_body.Body.initDynamic(shape, pos, .{ .rotation = rot_rad });
}

test "AABB Calculation and Basic Collision Tests" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    // const allocator = gpa.allocator(); // Not directly used by Body.aabb or rl funcs here

    // Scenario 1: Two Rectangles, AABBs DO NOT overlap
    const rect_shape1 = physics_shapes.PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 10, .height = 10 } }; // x,y in rl.Rect are for its top-left if not using a system that assumes center
    // For PhysicsShape, width/height are key for body's shape extent.
    const body1_pos = rl.Vector2{ .x = 0, .y = 0 };
    var body1_s1 = createTestStaticBody(rect_shape1, body1_pos, 0.0);
    body1_s1.id = 1;

    const rect_shape2 = physics_shapes.PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 10, .height = 10 } };
    const body2_pos_s1 = rl.Vector2{ .x = 20, .y = 0 }; // Far away
    var body2_s1 = createTestStaticBody(rect_shape2, body2_pos_s1, 0.0);
    body2_s1.id = 2;

    const aabb1_s1 = body1_s1.aabb(); // Body pos (0,0), shape w:10,h:10 -> AABB around (-5,-5) to (5,5)
    const aabb2_s1 = body2_s1.aabb(); // Body pos (20,0), shape w:10,h:10 -> AABB around (15,-5) to (25,5)

    std.debug.print("Scenario 1 - AABB1: {any}, AABB2: {any}\n", .{ aabb1_s1, aabb2_s1 });
    try testing.expect(!aabb1_s1.intersects(aabb2_s1));

    // Scenario 2: Two Axis-Aligned Rectangles, AABBs and Precise shapes DO overlap
    const body3_pos_s2 = rl.Vector2{ .x = 8, .y = 0 }; // Closer, should overlap
    var body3_s2 = createTestStaticBody(rect_shape2, body3_pos_s2, 0.0);
    body3_s2.id = 3;

    const aabb1_s2 = body1_s1.aabb(); // body1 is still at (0,0)
    const aabb3_s2 = body3_s2.aabb(); // Body pos (8,0), shape w:10,h:10 -> AABB around (3,-5) to (13,5)

    // std.debug.print("Scenario 2 - AABB1: {any}, AABB3: {any}\n", .{aabb1_s2, aabb3_s2});
    try testing.expect(aabb1_s2.intersects(aabb3_s2));

    // Precise check for axis-aligned rectangles (assuming body position is center)
    const world_rect1_s2 = rl.Rectangle{
        .x = body1_pos.x - rect_shape1.rectangle.width / 2.0,
        .y = body1_pos.y - rect_shape1.rectangle.height / 2.0,
        .width = rect_shape1.rectangle.width,
        .height = rect_shape1.rectangle.height,
    };
    const world_rect3_s2 = rl.Rectangle{
        .x = body3_pos_s2.x - rect_shape2.rectangle.width / 2.0,
        .y = body3_pos_s2.y - rect_shape2.rectangle.height / 2.0,
        .width = rect_shape2.rectangle.width,
        .height = rect_shape2.rectangle.height,
    };
    try testing.expect(rl.checkCollisionRecs(world_rect1_s2, world_rect3_s2));

    // Scenario 3: Two Circles, AABBs and Precise shapes DO overlap
    const circle_shape1 = physics_shapes.PhysicsShape{ .circle = .{ .radius = 5 } };
    var body4_s3 = createTestStaticBody(circle_shape1, body1_pos, 0.0); // body1_pos is (0,0)
    body4_s3.id = 4;

    const circle_shape2 = physics_shapes.PhysicsShape{ .circle = .{ .radius = 3 } };
    const body5_pos_s3 = rl.Vector2{ .x = 7, .y = 0 }; // Centers at (0,0) and (7,0). Radii 5 and 3. Sum = 8. Dist = 7. They overlap.
    var body5_s3 = createTestStaticBody(circle_shape2, body5_pos_s3, 0.0);
    body5_s3.id = 5;

    const aabb4_s3 = body4_s3.aabb(); // Circle @ (0,0) r5 -> AABB (-5,-5) to (5,5)
    const aabb5_s3 = body5_s3.aabb(); // Circle @ (7,0) r3 -> AABB (4,-3) to (10,3)

    std.debug.print("Scenario 3 - AABB4: {any}, AABB5: {any}\n", .{ aabb4_s3, aabb5_s3 });
    try testing.expect(aabb4_s3.intersects(aabb5_s3));
    try testing.expect(rl.checkCollisionCircles(body1_pos, circle_shape1.circle.radius, body5_pos_s3, circle_shape2.circle.radius));

    // Scenario 4: Rotated Rectangle AABB check
    // Body1 is rect at (0,0) w10,h10, rotation 0.
    // Body6 is rect at (5,0) w10,h10, rotation PI/4 radians (45 degrees)
    const PI: f32 = std.math.pi;
    var body6_s4 = createTestStaticBody(rect_shape1, rl.Vector2{ .x = 5, .y = 0 }, PI / 4.0);
    body6_s4.id = 6;

    const aabb1_s4 = body1_s1.aabb(); // Expected: min(-5,-5) max(5,5)
    const aabb6_s4 = body6_s4.aabb(); // Expected: AABB for a 10x10 rect centered at (5,0) rotated 45 deg.

    std.debug.print("Scenario 4 - AABB1: {any}, AABB6: {any}\n", .{ aabb1_s4, aabb6_s4 });
    try testing.expect(aabb1_s4.intersects(aabb6_s4)); // AABB of unrotated (-5,-5 to 5,5) should intersect AABB of rotated one.

    // Verify specific AABB values for the rotated rectangle (approximate)
    const epsilon = 0.01;
    try testing.expectApproxEqAbs(aabb6_s4.min.x, 5.0 - 5.0 * std.math.sqrt2, epsilon); // 5 - 5*sqrt(2)/2 - 5*sqrt(2)/2 = 5 - 5*sqrt(2) = 5 - 7.071 = -2.071
    try testing.expectApproxEqAbs(aabb6_s4.max.x, 5.0 + 5.0 * std.math.sqrt2, epsilon); // 5 + 7.071 = 12.071
    try testing.expectApproxEqAbs(aabb6_s4.min.y, 0.0 - 5.0 * std.math.sqrt2, epsilon); // 0 - 7.071 = -7.071
    try testing.expectApproxEqAbs(aabb6_s4.max.y, 0.0 + 5.0 * std.math.sqrt2, epsilon); // 0 + 7.071 = 7.071

}

test "Collision Detection System Tests" {
    std.debug.print("\n=== Collision Detection System Tests ===\n", .{});

    // Test 1: Circle-Circle Collision
    const circle1 = physics_shapes.PhysicsShape{ .circle = .{ .radius = 5.0 } };
    const circle2 = physics_shapes.PhysicsShape{ .circle = .{ .radius = 3.0 } };

    var body1 = createTestStaticBody(circle1, rl.Vector2{ .x = 0, .y = 0 }, 0.0);
    var body2 = createTestStaticBody(circle2, rl.Vector2{ .x = 6, .y = 0 }, 0.0); // Touching
    body1.id = 1;
    body2.id = 2;

    if (checkBodiesCollision(&body1, &body2)) |manifold| {
        std.debug.print("Circle-Circle Collision: penetration = {:.3}\n", .{manifold.penetration});
        try testing.expect(manifold.penetration > 0.0);
    } else {
        try testing.expect(false); // Should have collision
    }

    // Test 2: Rectangle-Rectangle Axis-Aligned
    const rect1 = physics_shapes.PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 10, .height = 10 } };
    const rect2 = physics_shapes.PhysicsShape{ .rectangle = .{ .x = 0, .y = 0, .width = 8, .height = 8 } };

    var body3 = createTestStaticBody(rect1, rl.Vector2{ .x = 0, .y = 0 }, 0.0);
    var body4 = createTestStaticBody(rect2, rl.Vector2{ .x = 7, .y = 0 }, 0.0); // Overlapping
    body3.id = 3;
    body4.id = 4;

    if (checkBodiesCollision(&body3, &body4)) |manifold| {
        std.debug.print("Rectangle-Rectangle Axis-Aligned: penetration = {:.3}\n", .{manifold.penetration});
        try testing.expect(manifold.penetration > 0.0);
    } else {
        try testing.expect(false); // Should have collision
    }

    // Test 3: SAT Rectangle-Rectangle with Rotation
    var body5 = createTestStaticBody(rect1, rl.Vector2{ .x = 0, .y = 0 }, 0.0);
    var body6 = createTestStaticBody(rect2, rl.Vector2{ .x = 7, .y = 0 }, std.math.pi / 4.0); // 45 degrees
    body5.id = 5;
    body6.id = 6;

    if (checkBodiesCollision(&body5, &body6)) |manifold| {
        std.debug.print("SAT Rectangle-Rectangle 45°: penetration = {:.3}\n", .{manifold.penetration});
        try testing.expect(manifold.penetration > 0.0);
    } else {
        std.debug.print("SAT Rectangle-Rectangle 45°: No collision detected\n", .{});
    }

    // Test 4: Circle-Rectangle Collision
    var body7 = createTestStaticBody(circle1, rl.Vector2{ .x = 0, .y = 0 }, 0.0);
    var body8 = createTestStaticBody(rect2, rl.Vector2{ .x = 6, .y = 0 }, 0.0);
    body7.id = 7;
    body8.id = 8;

    if (checkBodiesCollision(&body7, &body8)) |manifold| {
        std.debug.print("Circle-Rectangle: penetration = {:.3}\n", .{manifold.penetration});
        try testing.expect(manifold.penetration > 0.0);
    } else {
        std.debug.print("Circle-Rectangle: No collision detected\n", .{});
    }

    std.debug.print("=== Collision Detection Tests Complete ===\n", .{});
}

test "Sleep System Tests" {
    std.debug.print("\n=== Sleep System Tests ===\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a physics world with sleep enabled and NO GRAVITY
    var config = PhysicsConfig{};
    config.allow_sleeping = true;
    config.sleep_velocity_threshold = 0.1;
    config.sleep_time_threshold = 0.2; // Reduced from 0.5 for faster test
    config.gravity = rl.Vector2{ .x = 0.0, .y = 0.0 }; // Disable gravity for sleep test
    config.debug_draw_contacts = false; // Disable debug output

    var world = PhysicsWorld.init(allocator, config);
    defer world.deinit();

    // Add a dynamic body starting at rest
    const circle_shape = physics_shapes.PhysicsShape{ .circle = .{ .radius = 5.0 } };
    const dynamic_body = physics_body.Body.initDynamic(circle_shape, rl.Vector2{ .x = 0, .y = 0 }, .{
        .velocity = rl.Vector2{ .x = 0.0, .y = 0.0 }, // Stationary
    });

    const body_id = try world.addBody(dynamic_body);
    const body = world.getBody(body_id).?;

    // Test 1: Body should not be sleeping initially
    try testing.expect(!body.isSleeping());
    std.debug.print("Initial state: awake = {}\n", .{!body.isSleeping()});

    // Test 2: Simulate physics for enough time to trigger sleep
    for (0..10) |i| {
        world.update(0.1); // 0.1 seconds per step
        std.debug.print("Step {}: awake = {}, velocity = {:.3}\n", .{ i + 1, !body.isSleeping(), body.kind.Dynamic.velocity.x });

        if (i >= 6) { // After 0.7 seconds, should be asleep
            try testing.expect(body.isSleeping());
            break;
        }
    }

    // Test 3: Wake up body and verify it's awake
    body.wakeUp();
    try testing.expect(!body.isSleeping());
    std.debug.print("After wakeUp(): awake = {}\n", .{!body.isSleeping()});

    // Test 4: Manually put to sleep
    body.putToSleep();
    try testing.expect(body.isSleeping());
    try testing.expect(body.kind.Dynamic.velocity.x == 0.0);
    std.debug.print("After putToSleep(): sleeping = {}, velocity = {:.3}\n", .{ body.isSleeping(), body.kind.Dynamic.velocity.x });

    std.debug.print("=== Sleep System Tests Complete ===\n", .{});
}

test "Collision Response Tests" {
    std.debug.print("\n=== Collision Response Tests ===\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = PhysicsConfig{};
    var world = PhysicsWorld.init(allocator, config);
    defer world.deinit();

    // Create two dynamic bodies that will collide
    const circle_shape = physics_shapes.PhysicsShape{ .circle = .{ .radius = 5.0 } };

    const body1 = physics_body.Body.initDynamic(circle_shape, rl.Vector2{ .x = -8, .y = 0 }, .{
        .velocity = rl.Vector2{ .x = 10.0, .y = 0.0 }, // Moving right
        .mass = 1.0,
        .restitution = 0.8,
    });

    const body2 = physics_body.Body.initDynamic(circle_shape, rl.Vector2{ .x = 8, .y = 0 }, .{
        .velocity = rl.Vector2{ .x = -10.0, .y = 0.0 }, // Moving left
        .mass = 1.0,
        .restitution = 0.8,
    });

    const id1 = try world.addBody(body1);
    const id2 = try world.addBody(body2);

    const b1 = world.getBody(id1).?;
    const b2 = world.getBody(id2).?;

    std.debug.print("Before collision:\n", .{});
    std.debug.print("  Body1: pos=({:.1}, {:.1}), vel=({:.1}, {:.1})\n", .{ b1.getPosition().x, b1.getPosition().y, b1.kind.Dynamic.velocity.x, b1.kind.Dynamic.velocity.y });
    std.debug.print("  Body2: pos=({:.1}, {:.1}), vel=({:.1}, {:.1})\n", .{ b2.getPosition().x, b2.getPosition().y, b2.kind.Dynamic.velocity.x, b2.kind.Dynamic.velocity.y });

    // Simulate until collision happens
    var collision_detected = false;
    for (0..100) |i| {
        world.update(0.016); // ~60 FPS

        // Check if bodies have bounced (velocities should reverse)
        if (b1.kind.Dynamic.velocity.x < 0 and b2.kind.Dynamic.velocity.x > 0) {
            collision_detected = true;
            std.debug.print("Collision detected at step {}!\n", .{i + 1});
            std.debug.print("After collision:\n", .{});
            std.debug.print("  Body1: pos=({:.1}, {:.1}), vel=({:.1}, {:.1})\n", .{ b1.getPosition().x, b1.getPosition().y, b1.kind.Dynamic.velocity.x, b1.kind.Dynamic.velocity.y });
            std.debug.print("  Body2: pos=({:.1}, {:.1}), vel=({:.1}, {:.1})\n", .{ b2.getPosition().x, b2.getPosition().y, b2.kind.Dynamic.velocity.x, b2.kind.Dynamic.velocity.y });
            break;
        }
    }

    try testing.expect(collision_detected);

    // Verify collision response worked (velocities should have reversed)
    try testing.expect(b1.kind.Dynamic.velocity.x < 0); // Now moving left
    try testing.expect(b2.kind.Dynamic.velocity.x > 0); // Now moving right

    std.debug.print("=== Collision Response Tests Complete ===\n", .{});
}

test "Performance and Wake-up Tests" {
    std.debug.print("\n=== Performance and Wake-up Tests ===\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = PhysicsConfig{};
    config.allow_sleeping = true;
    config.sleep_velocity_threshold = 0.1;
    config.sleep_time_threshold = 0.1; // Sleep quickly for test
    config.gravity = rl.Vector2{ .x = 0.0, .y = 0.0 }; // Disable gravity so bodies can sleep

    var world = PhysicsWorld.init(allocator, config);
    defer world.deinit();

    // Add multiple stationary bodies that should go to sleep
    const circle_shape = physics_shapes.PhysicsShape{ .circle = .{ .radius = 2.0 } };
    var sleeping_bodies: [5]usize = undefined;

    for (0..5) |i| {
        const body = physics_body.Body.initDynamic(circle_shape, rl.Vector2{ .x = @as(f32, @floatFromInt(i)) * 6.0, .y = 0 }, .{
            .velocity = rl.Vector2{ .x = 0.0, .y = 0.0 }, // Stationary
        });
        sleeping_bodies[i] = try world.addBody(body);
    }

    // Let them all fall asleep
    for (0..5) |_| {
        world.update(0.1);
    }

    // Verify they're all asleep
    var all_sleeping = true;
    for (sleeping_bodies) |id| {
        if (!world.getBody(id).?.isSleeping()) {
            all_sleeping = false;
            break;
        }
    }
    try testing.expect(all_sleeping);
    std.debug.print("All 5 bodies put to sleep successfully\n", .{});

    // Add a fast-moving body that will collide with one of them
    const projectile = physics_body.Body.initDynamic(circle_shape, rl.Vector2{ .x = -10, .y = 0 }, .{
        .velocity = rl.Vector2{ .x = 20.0, .y = 0.0 }, // Fast moving
    });
    _ = try world.addBody(projectile);

    // Simulate collision - sleeping body should wake up
    var wake_up_detected = false;
    for (0..100) |i| {
        world.update(0.016);

        // Check if first sleeping body woke up
        const first_body = world.getBody(sleeping_bodies[0]).?;
        if (!first_body.isSleeping()) {
            wake_up_detected = true;
            std.debug.print("Sleeping body woke up after collision at step {}!\n", .{i + 1});
            break;
        }
    }

    try testing.expect(wake_up_detected);
    std.debug.print("Wake-up on collision works correctly\n", .{});

    std.debug.print("=== Performance and Wake-up Tests Complete ===\n", .{});
}
