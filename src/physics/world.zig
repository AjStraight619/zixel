const std = @import("std");
const Vec2 = @import("../math/vec2.zig");
const Body = @import("body.zig").Body;
const Allocator = std.mem.Allocator;
const narrowphase = @import("narrowphase.zig");
const checkBodiesCollision = narrowphase.NarrowPhase.checkBodiesCollision;
const ContactManifold = narrowphase.ContactManifold;
const CollisionResponse = @import("response.zig").CollisionResponse;

pub const PhysicsConfig = struct {
    // World settings
    gravity: Vec2 = Vec2{ .x = 0, .y = 980 }, // Positive Y = down (screen coords)

    // Solver settings
    position_iterations: u32 = 3,
    velocity_iterations: u32 = 8,

    // Timestep settings
    physics_time_step: f32 = 1.0 / 60.0, // Fixed physics timestep (60 FPS)
    max_delta_time: f32 = 1.0 / 30.0, // Maximum allowed delta time

    // Collision settings
    allow_sleeping: bool = true,
    sleep_time_threshold: f32 = 5.0,
    sleep_velocity_threshold: f32 = 15.0,

    // Contact settings
    contact_slop: f32 = 0.005,
    baumgarte_factor: f32 = 0.2,

    // Restitution clamp
    restitution_clamp_threshold: f32 = 15.0,
};

pub const World = @This();

alloc: Allocator,
bodies: std.ArrayList(Body),
config: PhysicsConfig,
next_id: usize = 0,

// Simulation state
accumulated_time: f32 = 0.0,
step_count: u64 = 0,

pub fn init(alloc: Allocator, config: PhysicsConfig) World {
    return .{
        .alloc = alloc,
        .bodies = .empty,
        .config = config,
    };
}

pub fn deinit(self: *World) void {
    self.bodies.deinit(self.alloc);
}

pub fn update(self: *World, delta_time: f32) void {
    // Clamp delta time to prevent spiral of death
    const clamped_dt = @min(delta_time, self.config.max_delta_time);
    self.accumulated_time += clamped_dt;

    // Fixed timestep physics simulation
    while (self.accumulated_time >= self.config.physics_time_step) {
        self.stepPhysics(self.config.physics_time_step);
        self.accumulated_time -= self.config.physics_time_step;
        self.step_count += 1;
    }
}

fn stepPhysics(self: *World, dt: f32) void {
    // Handle sleeping bodies FIRST
    if (self.config.allow_sleeping) {
        self.updateSleepingBodies(dt);
    }

    // Apply gravity and integrate forces (but NOT position yet)
    for (self.bodies.items) |*body| {
        if (body.kind == .dynamic and !body.isSleeping()) {
            // Apply gravity
            const gravity_force = Vec2{
                .x = self.config.gravity.x * body.mass,
                .y = self.config.gravity.y * body.mass,
            };
            body.applyForce(gravity_force);

            // Only update velocity from forces, NOT position yet
            body.velocity = body.velocity.add(body.acceleration.scale(dt));
            body.acceleration = Vec2.zero;
        }
    }

    // Collision detection and response BEFORE position integration
    self.detectAndResolveCollisions();

    // Position integration AFTER collision response
    for (self.bodies.items) |*body| {
        if (body.kind == .dynamic and !body.isSleeping()) {
            body.position = body.position.add(body.velocity.scale(dt));
        } else if (body.kind == .kinematic) {
            body.update(dt);
        }
    }
}

fn detectAndResolveCollisions(self: *World) void {
    var i: usize = 0;
    while (i < self.bodies.items.len) : (i += 1) {
        var body1_ptr = &self.bodies.items[i];

        var j: usize = i + 1;
        while (j < self.bodies.items.len) : (j += 1) {
            var body2_ptr = &self.bodies.items[j];

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
                    // Wake-up logic
                    const body1_is_active = !body1_ptr.isSleeping() and body1_ptr.kind == .dynamic;
                    const body2_is_active = !body2_ptr.isSleeping() and body2_ptr.kind == .dynamic;

                    if (body1_is_active or body2_is_active) {
                        const vel1 = body1_ptr.velocity;
                        const vel2 = body2_ptr.velocity;
                        const rel_vel = Vec2{ .x = vel2.x - vel1.x, .y = vel2.y - vel1.y };
                        const vel_along_normal = rel_vel.x * manifold.normal.x + rel_vel.y * manifold.normal.y;

                        if (vel_along_normal < -self.config.sleep_velocity_threshold) {
                            if (!body1_is_active) body1_ptr.wakeUp();
                            if (!body2_is_active) body2_ptr.wakeUp();
                        }
                    }

                    // Calculate combined restitution and friction
                    const restitution1 = body1_ptr.restitution;
                    const restitution2 = body2_ptr.restitution;
                    const friction1 = body1_ptr.friction;
                    const friction2 = body2_ptr.friction;

                    // Resolve collision with combined material properties
                    CollisionResponse.resolveCollisionWithMaterials(
                        body1_ptr,
                        body2_ptr,
                        manifold,
                        restitution1,
                        restitution2,
                        friction1,
                        friction2,
                        self.config.restitution_clamp_threshold,
                    );

                    // Position correction to reduce penetration
                    if (manifold.penetration > self.config.contact_slop) {
                        CollisionResponse.correctPositions(body1_ptr, body2_ptr, manifold, self.config.baumgarte_factor);
                    }
                }
            }
        }
    }
}

fn updateSleepingBodies(self: *World, dt: f32) void {
    for (self.bodies.items) |*body| {
        if (body.kind == .dynamic and !body.isSleeping()) {
            const velocity_mag = @sqrt(body.velocity.x * body.velocity.x +
                body.velocity.y * body.velocity.y);
            const angular_velocity_mag = @abs(body.angular_velocity);

            if (velocity_mag < self.config.sleep_velocity_threshold and
                angular_velocity_mag < self.config.sleep_velocity_threshold)
            {
                body.sleep_time += dt;
                if (body.sleep_time > self.config.sleep_time_threshold) {
                    body.putToSleep();
                }
            } else {
                body.sleep_time = 0.0;
            }
        }
    }
}

/// Add a body to the world and return its ID
pub fn addBody(self: *World, body: Body) !usize {
    const id = self.next_id;
    self.next_id += 1;

    var new_body = body;
    new_body.id = id;

    try self.bodies.append(self.alloc, new_body);
    return id;
}

/// Get a body by ID
pub fn getBodyById(self: *World, id: usize) ?*Body {
    for (self.bodies.items) |*body| {
        if (body.id == id) return body;
    }
    return null;
}

/// Remove a body by index
pub fn removeBody(self: *World, index: usize) void {
    if (index >= self.bodies.items.len) return;
    _ = self.bodies.swapRemove(index);
}

/// Remove a body by ID
pub fn removeBodyById(self: *World, id: usize) bool {
    for (self.bodies.items, 0..) |*body, i| {
        if (body.id == id) {
            self.removeBody(i);
            return true;
        }
    }
    return false;
}

/// Clear all bodies from the world
pub fn clearBodies(self: *World) void {
    self.bodies.clearAndFree(self.alloc);
}
