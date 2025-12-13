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
const SpatialHash = @import("broadphase.zig").SpatialHash;

const Ctx = struct {
    world: *World,
    iter: usize,
};

pub const PhysicsConfig = struct {
    // World settings
    gravity: Vec2 = Vec2{ .x = 0, .y = 980 }, // Positive Y = down (screen coords)

    // Solver settings
    position_iterations: u32 = 8, // More iterations for stable stacking
    velocity_iterations: u32 = 8,

    // Timestep settings
    physics_time_step: f32 = 1.0 / 60.0, // Fixed physics timestep (60 FPS)
    max_delta_time: f32 = 1.0 / 30.0, // Maximum allowed delta time

    // Collision settings
    allow_sleeping: bool = true,
    sleep_time_threshold: f32 = 0.3, // Seconds of stillness before sleep
    sleep_velocity_threshold: f32 = 25.0, // Velocity below which body is "still" (raised!)

    // Contact settings
    contact_slop: f32 = 0.3, // Allow tiny penetration before correction
    baumgarte_factor: f32 = 0.5, // Position correction strength

    // Restitution clamp
    restitution_clamp_threshold: f32 = 3.0, // Kill bounce below this velocity

    // Damping (helps stacks settle and reduces jitter)
    linear_damping: f32 = 0.02, // 2% velocity reduction per step (0 = none, 1 = instant stop)

    // Debug
    debug_logging: bool = false,
    debug_log_interval: u64 = 60, // Log every N physics steps
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

/// Debug stats collected each frame
pub const DebugStats = struct {
    active_bodies: u32 = 0,
    sleeping_bodies: u32 = 0,
    collision_checks: u32 = 0,
    collisions_found: u32 = 0,
    max_penetration: f32 = 0,
    max_velocity: f32 = 0,
};

alloc: Allocator,
slots: std.ArrayList(BodySlot),
free_indices: std.ArrayList(u32),
spatial_hash: SpatialHash,
cfg: PhysicsConfig,

// Simulation state
accumulated_time: f32 = 0.0,
step_count: u64 = 0,

// Debug
debug_stats: DebugStats = .{},

pub fn init(alloc: Allocator, cfg: PhysicsConfig) PhysicsConfigError!World {
    try validateConfig(cfg);
    return .{
        .alloc = alloc,
        .slots = .empty,
        .free_indices = .empty,
        .spatial_hash = SpatialHash.init(alloc, 64.0), // 64px cells
        .cfg = cfg,
    };
}

pub fn deinit(self: *World) void {
    self.spatial_hash.deinit();
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
    // Reset debug stats
    self.debug_stats = .{};

    // Update sleep state first (optional)
    if (self.cfg.allow_sleeping) {
        self.updateSleepingBodies(dt);
    }

    for (self.slots.items) |*slot| {
        if (!slot.alive) continue;
        const body = &slot.body;

        // Debug counts / max velocity
        if (body.kind == .dynamic) {
            if (body.isSleeping()) {
                self.debug_stats.sleeping_bodies += 1;
            } else {
                self.debug_stats.active_bodies += 1;
                const vel_mag = @sqrt(body.velocity.x * body.velocity.x + body.velocity.y * body.velocity.y);
                self.debug_stats.max_velocity = @max(self.debug_stats.max_velocity, vel_mag);
            }
        }

        if (body.kind == .dynamic and !body.isSleeping()) {
            // Gravity as a force (your applyForce divides by mass -> acceleration)
            body.applyForce(Vec2{
                .x = self.cfg.gravity.x * body.mass,
                .y = self.cfg.gravity.y * body.mass,
            });

            // Integrate velocity
            body.velocity = body.velocity.add(body.acceleration.scale(dt));
            body.acceleration = Vec2.zero;
        }
    }

    for (self.slots.items) |*slot| {
        if (!slot.alive) continue;
        const body = &slot.body;

        switch (body.kind) {
            .dynamic => {
                if (!body.isSleeping()) {
                    body.position = body.position.add(body.velocity.scale(dt));
                }
            },
            .kinematic => {
                body.position = body.position.add(body.velocity.scale(dt));
            },
            .static => {},
        }
    }

    self.detectAndResolveCollisions();

    if (self.cfg.linear_damping > 0) {
        const damping = 1.0 - self.cfg.linear_damping;
        for (self.slots.items) |*slot| {
            if (!slot.alive) continue;
            const body = &slot.body;

            if (body.kind == .dynamic and !body.isSleeping()) {
                body.velocity = body.velocity.scale(damping);
            }
        }
    }

    if (self.cfg.debug_logging and self.step_count % self.cfg.debug_log_interval == 0) {
        log.info("[Physics] step={d} active={d} sleeping={d} collisions={d}/{d} max_pen={d:.2} max_vel={d:.1}", .{
            self.step_count,
            self.debug_stats.active_bodies,
            self.debug_stats.sleeping_bodies,
            self.debug_stats.collisions_found,
            self.debug_stats.collision_checks,
            self.debug_stats.max_penetration,
            self.debug_stats.max_velocity,
        });
    }
}

fn detectAndResolveCollisions(self: *World) void {
    for (0..self.cfg.position_iterations) |iter| {
        self.spatial_hash.clear();
        for (self.slots.items) |*slot| {
            if (!slot.alive) continue;
            self.spatial_hash.insert(&slot.body);
        }

        const ctx = Ctx{ .world = self, .iter = iter };
        self.spatial_hash.forEachPair(ctx, processCollisionPairIter);
    }
}

fn processCollisionPairIter(ctx: Ctx, body1: *Body, body2: *Body) void {
    const self = ctx.world;

    if (body1.kind != .dynamic and body2.kind != .dynamic) return;

    self.debug_stats.collision_checks += 1;

    const aabb1 = body1.aabb();
    const aabb2 = body2.aabb();
    if (!aabb1.intersects(aabb2)) return;

    if (checkBodiesCollision(body1, body2)) |manifold| {
        self.debug_stats.collisions_found += 1;
        self.debug_stats.max_penetration = @max(self.debug_stats.max_penetration, manifold.penetration);

        // Apply velocity impulses ONLY once per step (iter == 0)
        if (ctx.iter == 0) {
            CollisionResponse.resolveCollisionWithMaterials(
                body1,
                body2,
                manifold,
                body1.restitution,
                body2.restitution,
                body1.friction,
                body2.friction,
                self.cfg.restitution_clamp_threshold,
            );
        }

        // Still do position correction each iteration
        if (manifold.penetration > self.cfg.contact_slop) {
            CollisionResponse.correctPositions(body1, body2, manifold, self.cfg.baumgarte_factor);
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
        return PhysicsConfigError.MaxDeltaLessThanStep;
    }

    if (cfg.sleep_time_threshold < 0) {
        log.err("sleep_time_threshold must be >= 0 (got {})", .{cfg.sleep_time_threshold});
        return PhysicsConfigError.NegativeSleepThreshold;
    }

    if (cfg.sleep_velocity_threshold < 0) {
        log.err("sleep_velocity_threshold must be >= 0 (got {})", .{cfg.sleep_velocity_threshold});
        return PhysicsConfigError.NegativeSleepVelocity;
    }

    if (cfg.baumgarte_factor < 0) {
        log.err("baumgarte_factor must be >= 0 (got {})", .{cfg.baumgarte_factor});
        return PhysicsConfigError.NegativeBaumgarte;
    }

    if (cfg.restitution_clamp_threshold < 0) {
        log.err("restitution_clamp_threshold must be >= 0 (got {})", .{cfg.restitution_clamp_threshold});
        return PhysicsConfigError.NegativeRestitutionClamp;
    }
}
