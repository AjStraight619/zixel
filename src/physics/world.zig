const std = @import("std");
const log = std.log;
const Vec2 = @import("../math/vec2.zig");
const body_mod = @import("body.zig");
const Body = body_mod.Body;
const BodyOptions = body_mod.BodyOptions;
const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
const Allocator = std.mem.Allocator;
const narrowphase = @import("narrowphase.zig");
const checkBodiesCollision = narrowphase.NarrowPhase.checkBodiesCollision;
const ContactManifold = narrowphase.ContactManifold;
const CollisionResponse = @import("response.zig").CollisionResponse;
pub const BodyHandle = @import("handle.zig").BodyHandle;

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

const PhysicsConfigError = error{
    InvalidTimeStep,
    MaxDeltaTooSmall,
    MaxDeltaLessThanStep,
    NegativeSleepThreshold,
    NegativeSleepVelocity,
    NegativeBaumgarte,
    NegativeRestitutionClamp,
};

pub const World = @This();

/// A slot in the body storage array.
/// Contains the body data plus metadata for generational handle tracking.
pub const BodySlot = struct {
    body: Body,
    generation: u32 = 1,
    alive: bool = false,
};

alloc: Allocator,
slots: std.ArrayList(BodySlot),
free_indices: std.ArrayList(u32),
cfg: PhysicsConfig,

// Simulation state
accumulated_time: f32 = 0.0,
step_count: u64 = 0,

pub fn init(alloc: Allocator, cfg: PhysicsConfig) PhysicsConfigError!World {
    try validateConfig(cfg);
    return .{
        .alloc = alloc,
        .slots = .empty,
        .free_indices = .empty,
        .cfg = cfg,
    };
}

pub fn deinit(self: *World) void {
    self.slots.deinit(self.alloc);
    self.free_indices.deinit(self.alloc);
}

pub fn update(self: *World, delta_time: f32) void {
    // Clamp delta time to prevent spiral of death
    const clamped_dt = @min(delta_time, self.cfg.max_delta_time);
    self.accumulated_time += clamped_dt;

    // Fixed timestep physics simulation
    while (self.accumulated_time >= self.cfg.physics_time_step) {
        self.stepPhysics(self.cfg.physics_time_step);
        self.accumulated_time -= self.cfg.physics_time_step;
        self.step_count += 1;
    }
}

fn stepPhysics(self: *World, dt: f32) void {
    // Handle sleeping bodies FIRST
    if (self.cfg.allow_sleeping) {
        self.updateSleepingBodies(dt);
    }

    // Apply gravity and integrate forces (but NOT position yet)
    for (self.slots.items) |*slot| {
        if (!slot.alive) continue;
        const body = &slot.body;
        if (body.kind == .dynamic and !body.isSleeping()) {
            // Apply gravity
            const gravity_force = Vec2{
                .x = self.cfg.gravity.x * body.mass,
                .y = self.cfg.gravity.y * body.mass,
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
    for (self.slots.items) |*slot| {
        if (!slot.alive) continue;
        const body = &slot.body;
        if (body.kind == .dynamic and !body.isSleeping()) {
            body.position = body.position.add(body.velocity.scale(dt));
        } else if (body.kind == .kinematic) {
            body.update(dt);
        }
    }
}

fn detectAndResolveCollisions(self: *World) void {
    const slots = self.slots.items;

    var i: usize = 0;
    while (i < slots.len) : (i += 1) {
        if (!slots[i].alive) continue;
        var body1_ptr = &slots[i].body;

        var j: usize = i + 1;
        while (j < slots.len) : (j += 1) {
            if (!slots[j].alive) continue;
            var body2_ptr = &slots[j].body;

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

                        if (vel_along_normal < -self.cfg.sleep_velocity_threshold) {
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
                        self.cfg.restitution_clamp_threshold,
                    );

                    // Position correction to reduce penetration
                    if (manifold.penetration > self.cfg.contact_slop) {
                        CollisionResponse.correctPositions(body1_ptr, body2_ptr, manifold, self.cfg.baumgarte_factor);
                    }
                }
            }
        }
    }
}

fn updateSleepingBodies(self: *World, dt: f32) void {
    for (self.slots.items) |*slot| {
        if (!slot.alive) continue;
        const body = &slot.body;
        if (body.kind == .dynamic and !body.isSleeping()) {
            const velocity_mag = @sqrt(body.velocity.x * body.velocity.x +
                body.velocity.y * body.velocity.y);
            const angular_velocity_mag = @abs(body.angular_velocity);

            if (velocity_mag < self.cfg.sleep_velocity_threshold and
                angular_velocity_mag < self.cfg.sleep_velocity_threshold)
            {
                body.sleep_time += dt;
                if (body.sleep_time > self.cfg.sleep_time_threshold) {
                    body.putToSleep();
                }
            } else {
                body.sleep_time = 0.0;
            }
        }
    }
}

/// Add a body to the world and return a handle to it.
/// The handle can be used for O(1) lookup and is safe against stale references.
pub fn addBody(self: *World, body: Body) !BodyHandle {
    // Try to reuse a free slot first (pop returns optional in Zig 0.14+)
    if (self.free_indices.pop()) |free_index| {
        const slot = &self.slots.items[free_index];
        slot.body = body;
        slot.alive = true;
        // Generation was already bumped when slot was freed
        return BodyHandle{
            .index = free_index,
            .generation = slot.generation,
        };
    }

    // No free slot - allocate a new one
    const index: u32 = @intCast(self.slots.items.len);
    try self.slots.append(self.alloc, BodySlot{
        .body = body,
        .generation = 1,
        .alive = true,
    });

    return BodyHandle{
        .index = index,
        .generation = 1,
    };
}

/// Get a body by handle. Returns null if handle is invalid or stale.
pub fn getBody(self: *World, handle: BodyHandle) ?*Body {
    if (handle.index >= self.slots.items.len) return null;

    const slot = &self.slots.items[handle.index];
    if (!slot.alive or slot.generation != handle.generation) return null;

    return &slot.body;
}

/// Get a body by handle (const version).
pub fn getBodyConst(self: *const World, handle: BodyHandle) ?*const Body {
    if (handle.index >= self.slots.items.len) return null;

    const slot = &self.slots.items[handle.index];
    if (!slot.alive or slot.generation != handle.generation) return null;

    return &slot.body;
}

/// Remove a body by handle. Returns true if the body was found and removed.
pub fn removeBody(self: *World, handle: BodyHandle) bool {
    if (handle.index >= self.slots.items.len) return false;

    const slot = &self.slots.items[handle.index];
    if (!slot.alive or slot.generation != handle.generation) return false;

    slot.alive = false;
    // Bump generation so old handles become invalid
    slot.generation +%= 1;
    // Add to free list for reuse
    self.free_indices.append(self.alloc, handle.index) catch {};

    return true;
}

/// Clear all bodies from the world.
pub fn clearBodies(self: *World) void {
    // Mark all slots as dead and bump generations
    for (self.slots.items) |*slot| {
        if (slot.alive) {
            slot.alive = false;
            slot.generation +%= 1;
        }
    }
    // Rebuild free list with all indices
    self.free_indices.clearRetainingCapacity();
    for (0..self.slots.items.len) |i| {
        self.free_indices.append(self.alloc, @intCast(i)) catch {};
    }
}

/// Returns the number of alive bodies in the world.
pub fn bodyCount(self: *const World) usize {
    var count: usize = 0;
    for (self.slots.items) |slot| {
        if (slot.alive) count += 1;
    }
    return count;
}

// ============================================================================
// Convenience methods for adding common body types
// ============================================================================

/// Add a static rectangle body
pub fn addStaticRect(self: *World, x: f32, y: f32, w: f32, h: f32, opts: BodyOptions) !BodyHandle {
    return self.addBody(Body.initStatic(PhysicsShape.rect(w, h), Vec2.init(x, y), opts));
}

/// Add a dynamic rectangle body
pub fn addDynamicRect(self: *World, x: f32, y: f32, w: f32, h: f32, opts: BodyOptions) !BodyHandle {
    return self.addBody(Body.initDynamic(PhysicsShape.rect(w, h), Vec2.init(x, y), opts));
}

/// Add a kinematic rectangle body
pub fn addKinematicRect(self: *World, x: f32, y: f32, w: f32, h: f32, opts: BodyOptions) !BodyHandle {
    return self.addBody(Body.initKinematic(PhysicsShape.rect(w, h), Vec2.init(x, y), opts));
}

/// Add a static circle body
pub fn addStaticCircle(self: *World, x: f32, y: f32, radius: f32, opts: BodyOptions) !BodyHandle {
    return self.addBody(Body.initStatic(PhysicsShape.circ(radius), Vec2.init(x, y), opts));
}

/// Add a dynamic circle body
pub fn addDynamicCircle(self: *World, x: f32, y: f32, radius: f32, opts: BodyOptions) !BodyHandle {
    return self.addBody(Body.initDynamic(PhysicsShape.circ(radius), Vec2.init(x, y), opts));
}

/// Add a kinematic circle body
pub fn addKinematicCircle(self: *World, x: f32, y: f32, radius: f32, opts: BodyOptions) !BodyHandle {
    return self.addBody(Body.initKinematic(PhysicsShape.circ(radius), Vec2.init(x, y), opts));
}

fn validateConfig(cfg: PhysicsConfig) PhysicsConfigError!void {
    if (cfg.physics_time_step <= 0) {
        log.err("physics_time_step must be > 0 (got {})", .{cfg.physics_time_step});
        return PhysicsConfigError.InvalidTimeStep;
    }

    if (cfg.max_delta_time <= 0) {
        log.err("max_delta_time must be > 0 (got {})", .{cfg.max_delta_time});
        return PhysicsConfigError.MaxDeltaTooSmall;
    }

    if (cfg.max_delta_time < cfg.physics_time_step) {
        log.err(
            "max_delta_time ({}) must be >= physics_time_step ({})",
            .{ cfg.max_delta_time, cfg.physics_time_step },
        );
        return error.MaxDeltaLessThanStep;
    }

    if (cfg.sleep_time_threshold < 0) {
        log.err("sleep_time_threshold must be >= 0 (got {})", .{cfg.sleep_time_threshold});
        return error.NegativeSleepThreshold;
    }

    if (cfg.sleep_velocity_threshold < 0) {
        log.err("sleep_velocity_threshold must be >= 0 (got {})", .{cfg.sleep_velocity_threshold});
        return error.NegativeSleepVelocity;
    }

    if (cfg.baumgarte_factor < 0) {
        log.err("baumgarte_factor must be >= 0 (got {})", .{cfg.baumgarte_factor});
        return error.NegativeBaumgarte;
    }

    if (cfg.restitution_clamp_threshold < 0) {
        log.err("restitution_clamp_threshold must be >= 0 (got {})", .{cfg.restitution_clamp_threshold});
        return error.NegativeRestitutionClamp;
    }
}
