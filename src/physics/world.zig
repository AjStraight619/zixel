const std = @import("std");
const rl = @import("raylib"); // Import raylib
const PhysicsConfig = @import("config.zig").PhysicsConfig;
const Allocator = std.mem.Allocator;
const Body = @import("body.zig").Body;
const Vector2 = rl.Vector2; // Use Raylib's Vector2

pub const PhysicsWorld = struct {
    allocator: std.mem.Allocator,
    bodies: std.ArrayList(Body),
    config: PhysicsConfig,
    next_id: usize = 0,
    gravity: Vector2,

    // Simulation state
    accumulated_time: f32 = 0.0,
    step_count: u64 = 0,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, config: PhysicsConfig) !Self {
        return Self{
            .allocator = alloc,
            .bodies = std.ArrayList(Body).init(alloc),
            .config = config,
            .gravity = config.gravity,
        };
    }

    pub fn deinit(self: *Self) void {
        self.bodies.deinit();
    }

    pub fn update(self: *Self, deltaTime: f32) void {
        // Clamp delta time to prevent spiral of death
        const clamped_dt = @min(deltaTime, self.config.max_delta_time);
        self.accumulated_time += clamped_dt;

        // Fixed timestep physics simulation
        while (self.accumulated_time >= self.config.physics_time_step) {
            self.stepPhysics(self.config.physics_time_step);
            self.accumulated_time -= self.config.physics_time_step;
            self.step_count += 1;
        }
    }

    fn stepPhysics(self: *Self, dt: f32) void {
        // Apply gravity and integrate forces
        for (self.bodies.items) |*body| {
            if (body.isDynamic()) {
                // Apply gravity
                const gravity_force = Vector2{
                    .x = self.config.gravity.x * body.kind.Dynamic.mass,
                    .y = self.config.gravity.y * body.kind.Dynamic.mass,
                };
                body.applyForce(gravity_force);
            }
        }

        // Velocity iterations - integrate velocities
        for (0..self.config.velocity_iterations) |_| {
            for (self.bodies.items) |*body| {
                if (body.isDynamic()) {
                    body.update(dt);
                }
            }
        }

        // Collision detection and response
        self.detectAndResolveCollisions();

        // Position iterations - correct positions
        for (0..self.config.position_iterations) |_| {
            // Position correction would go here
            // For now, we'll just ensure bodies are updated
            for (self.bodies.items) |*body| {
                if (body.isDynamic()) {
                    // Additional position correction could be applied here
                    // TODO: Implement position correction using config.baumgarte_factor
                }
            }
        }

        // Handle sleeping bodies if enabled
        if (self.config.allow_sleeping) {
            self.updateSleepingBodies(dt);
        }
    }

    fn detectAndResolveCollisions(self: *Self) void {
        // Broadphase: O(n²) collision detection
        // In a real engine, you'd use spatial partitioning (quadtree, spatial hash, etc.)
        var i: usize = 0;
        while (i < self.bodies.items.len) : (i += 1) {
            var body1_ptr = &self.bodies.items[i];

            var j: usize = i + 1;
            while (j < self.bodies.items.len) : (j += 1) {
                var body2_ptr = &self.bodies.items[j];

                // Skip collision between two static bodies
                if (!body1_ptr.isDynamic() and !body2_ptr.isDynamic()) {
                    continue;
                }

                // Broadphase: AABB collision
                const aabb1 = body1_ptr.aabb();
                const aabb2 = body2_ptr.aabb();

                if (aabb1.intersects(aabb2)) {
                    // Narrowphase collision detection would go here
                    // For now, we'll just log potential collisions
                    if (self.config.debug_draw_contacts) {
                        std.debug.print("Potential collision between body {} and {}\n", .{ body1_ptr.id, body2_ptr.id });
                    }

                    // TODO: Implement detailed collision detection and response
                    // This would include:
                    // - Shape-specific collision checks (circle-circle, rect-rect, circle-rect)
                    // - Contact manifold generation
                    // - Impulse resolution
                    // - Position correction using baumgarte_factor
                }
            }
        }
    }

    fn updateSleepingBodies(self: *Self, dt: f32) void {
        for (self.bodies.items) |*body| {
            if (body.isDynamic()) {
                const velocity_mag = @sqrt(body.kind.Dynamic.velocity.x * body.kind.Dynamic.velocity.x +
                    body.kind.Dynamic.velocity.y * body.kind.Dynamic.velocity.y);

                if (velocity_mag < self.config.sleep_velocity_threshold) {
                    // Body is slow enough to potentially sleep
                    // In a full implementation, you'd track sleep time per body
                    _ = dt; // Would use dt to track sleep time
                    // body.sleep_time += dt;
                    // if (body.sleep_time > self.config.sleep_time_threshold) {
                    //     body.is_sleeping = true;
                    // }
                }
            }
        }
    }

    pub fn getPhysicsTimeStep(self: *const Self) f32 {
        return self.config.physics_time_step;
    }

    pub fn getStepCount(self: *const Self) u64 {
        return self.step_count;
    }

    pub fn addBody(self: *Self, body: Body) !usize {
        try self.bodies.append(body);
        const id = self.bodies.items.len - 1;
        self.bodies.items[id].id = id;
        return id;
    }

    pub fn getBody(self: *Self, id: usize) ?*Body {
        if (id < self.bodies.items.len) {
            return &self.bodies.items[id];
        }
        return null;
    }

    pub fn removeBody(self: *Self, index: usize) void {
        self.bodies.swapRemove(index);
    }

    pub fn getBodyCount(self: *Self) usize {
        return self.bodies.items.len;
    }

    // Placeholder - actual collision resolution would be more complex
    // fn resolveCollision(body1: *Body, body2: *Body) void {
    //     // ... impulse calculations, position correction ...
    // }
};

//-------------
// TEST CODE
//-------------
const testing = @import("std").testing;
const core_math = @import("../core/math/aabb.zig"); // For AABB
const physics_body = @import("body.zig"); // For Body, StaticBodyOptions etc.
const physics_shapes = @import("../core/math/shapes.zig"); // For PhysicsShape

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
    // Corners of unrotated local rect: (-5,-5), (5,-5), (5,5), (-5,5)
    // Rotated by 45deg (cos45=sin45=~0.707):
    // (-5,-5) -> (-5*0.707 - -5*0.707, -5*0.707 + -5*0.707) = (0, -7.07) -> world (5, -7.07)
    // (5,-5)  -> (5*0.707 - -5*0.707,  5*0.707 + -5*0.707) = (7.07, 0)  -> world (12.07, 0)
    // (5,5)   -> (5*0.707 -  5*0.707,  5*0.707 +  5*0.707) = (0, 7.07)   -> world (5, 7.07)
    // (-5,5)  -> (-5*0.707 - 5*0.707, -5*0.707 +  5*0.707) = (-7.07, 0) -> world (-2.07, 0)
    // So, AABB6 min_x approx -2.07, max_x approx 12.07. min_y approx -7.07, max_y approx 7.07.

    std.debug.print("Scenario 4 - AABB1: {any}, AABB6: {any}\n", .{ aabb1_s4, aabb6_s4 });
    try testing.expect(aabb1_s4.intersects(aabb6_s4)); // AABB of unrotated (-5,-5 to 5,5) should intersect AABB of rotated one.

    // Verify specific AABB values for the rotated rectangle (approximate)
    const epsilon = 0.01;
    try testing.expectApproxEqAbs(aabb6_s4.min.x, 5.0 - 5.0 * std.math.sqrt2, epsilon); // 5 - 5*sqrt(2)/2 - 5*sqrt(2)/2 = 5 - 5*sqrt(2) = 5 - 7.071 = -2.071
    try testing.expectApproxEqAbs(aabb6_s4.max.x, 5.0 + 5.0 * std.math.sqrt2, epsilon); // 5 + 7.071 = 12.071
    try testing.expectApproxEqAbs(aabb6_s4.min.y, 0.0 - 5.0 * std.math.sqrt2, epsilon); // 0 - 7.071 = -7.071
    try testing.expectApproxEqAbs(aabb6_s4.max.y, 0.0 + 5.0 * std.math.sqrt2, epsilon); // 0 + 7.071 = 7.071
    // The manual calculation above for corners was a bit off; the AABB of a square rotated 45deg with side L centered at (cx,cy)
    // has min/max x = cx +/- L/sqrt(2), min/max y = cy +/- L/sqrt(2). Here L=10sqrt(2) is diagonal, side is 10.
    // Half-diagonal is 5*sqrt(2). So corners are at distance 5*sqrt(2) from center along axes rotated by 45.
    // AABB extents from center: L * (cos(a) + sin(a))/2 where a is angle from local x-axis to aabb edge.
    // Simpler: for a square of side S, rotated 45deg, AABB width/height is S*sqrt(2).
    // So for side 10, AABB width/height is 10*sqrt(2) ~ 14.14.
    // Centered at (5,0), AABB min x = 5 - 14.14/2 = 5 - 7.07 = -2.07
    // AABB max x = 5 + 7.07 = 12.07
    // AABB min y = 0 - 7.07 = -7.07
    // AABB max y = 0 + 7.07 = 7.07
    // These are the values used in expectApproxEqAbs.
}
