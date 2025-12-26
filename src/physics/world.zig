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

const CollisionResponse = @import("response.zig");

pub const BodyHandle = @import("handle.zig").BodyHandle;

const SpatialHash = @import("broadphase.zig").SpatialHash;

/// Context passed into broadphase callbacks.
/// `iter` is the current position-correction iteration.
const Ctx = struct {
    world: *World,
    iter: usize,
};

pub const Config = struct {
    // World settings
    gravity: Vec2 = Vec2{ .x = 0, .y = 980 }, // Positive Y = down (screen coords)

    // Solver settings
    // Note: In this engine we apply *velocity impulses once per step*,
    // and do positional correction multiple times for stability.
    position_iterations: u32 = 8,
    velocity_iterations: u32 = 8, // currently unused (reserved for future multi-iter velocity solve)

    // Timestep settings
    physics_time_step: f32 = 1.0 / 60.0,
    max_delta_time: f32 = 1.0 / 30.0,

    // Sleeping
    allow_sleeping: bool = true,
    sleep_time_threshold: f32 = 0.3,
    sleep_velocity_threshold: f32 = 25.0,

    // Contact correction
    contact_slop: f32 = 0.3,
    baumgarte_factor: f32 = 0.5,

    // Restitution clamp
    restitution_clamp_threshold: f32 = 3.0,

    // Damping (per step)
    linear_damping: f32 = 0.002, // 0.2% velocity reduction per physics step
    angular_damping: f32 = 0.05, // 5% angular velocity reduction per step (rotation needs more damping)

    // Velocity limits (prevents instability)
    max_linear_velocity: f32 = 2000.0, // pixels/sec
    max_angular_velocity: f32 = 20.0, // radians/sec (~3 rotations/sec)

    // Debug
    debug_logging: bool = false,
    debug_log_interval: u64 = 60,
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

const World = @This();

/// Storage slot for generational handles.
pub const BodySlot = struct {
    body: Body,
    generation: u32 = 1,
    alive: bool = false,
};

/// Debug stats collected each physics step.
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
cfg: Config,

// Fixed-step accumulator state
accumulated_time: f32 = 0.0,
step_count: u64 = 0,

// Debug
debug_stats: DebugStats = .{},

pub fn init(alloc: Allocator, cfg: Config) PhysicsConfigError!World {
    try validateConfig(cfg);
    return .{
        .alloc = alloc,
        .slots = .empty,
        .free_indices = .empty,
        .spatial_hash = SpatialHash.init(alloc, 64.0),
        .cfg = cfg,
    };
}

pub fn deinit(self: *World) void {
    self.spatial_hash.deinit();
    self.slots.deinit(self.alloc);
    self.free_indices.deinit(self.alloc);
}

/// Public update with variable dt; internally runs fixed-timestep simulation.
pub fn update(self: *World, delta_time: f32) void {
    const clamped_dt = @min(delta_time, self.cfg.max_delta_time);
    self.accumulated_time += clamped_dt;

    while (self.accumulated_time >= self.cfg.physics_time_step) {
        self.stepPhysics(self.cfg.physics_time_step);
        self.accumulated_time -= self.cfg.physics_time_step;
        self.step_count += 1;
    }
}

pub fn forEachBodyConst(self: *const World, ctx: anytype, comptime func: anytype) void {
    for (self.slots.items) |*slot| {
        if (!slot.alive) continue;
        func(ctx, &slot.body);
    }
}

fn stepPhysics(self: *World, dt: f32) void {
    self.debug_stats = .{};

    if (self.cfg.allow_sleeping) {
        self.updateSleepingBodies(dt);
    }

    self.integrateVelocities(dt);
    self.integratePositions(dt);

    self.solveCollisions();

    self.applyDamping();

    self.maybeLogDebug();
}

fn integrateVelocities(self: *World, dt: f32) void {
    for (self.slots.items) |*slot| {
        if (!slot.alive) continue;
        const body = &slot.body;

        // Debug stats
        if (body.kind == .dynamic) {
            if (body.isSleeping()) {
                self.debug_stats.sleeping_bodies += 1;
            } else {
                self.debug_stats.active_bodies += 1;
                const vel_mag = @sqrt(body.velocity.x * body.velocity.x + body.velocity.y * body.velocity.y);
                self.debug_stats.max_velocity = @max(self.debug_stats.max_velocity, vel_mag);
            }
        }

        if (body.kind != .dynamic or body.isSleeping()) continue;

        // Gravity (force = m*g)
        body.applyForce(Vec2{
            .x = self.cfg.gravity.x * body.mass,
            .y = self.cfg.gravity.y * body.mass,
        });

        // Linear velocity: v += a * dt
        body.velocity = body.velocity.add(body.acceleration.scale(dt));
        body.acceleration = Vec2.zero;

        // Angular velocity: w += alpha * dt
        body.angular_velocity += body.angular_acceleration * dt;
        body.angular_acceleration = 0.0;
    }
}

fn integratePositions(self: *World, dt: f32) void {
    for (self.slots.items) |*slot| {
        if (!slot.alive) continue;
        const body = &slot.body;

        switch (body.kind) {
            .dynamic => {
                if (body.isSleeping()) continue;
                body.position = body.position.add(body.velocity.scale(dt));
                body.rotation += body.angular_velocity * dt;
                // Ensures rotations stays between -pi to pi
                body.rotation = std.math.wrap(body.rotation, std.math.pi);
            },
            .kinematic => {
                body.position = body.position.add(body.velocity.scale(dt));
                // If you later add kinematic angular velocity, update rotation here too.
            },
            .static => {},
        }
    }
}

/// Collision solve design:
/// - Apply velocity impulses once per step (stable + cheap)
/// - Apply positional correction multiple times for stack stability
// fn solveCollisions(self: *World) void {
//     // Iter 0: does impulses + correction
//     // Iter 1..N: does correction only
//     for (0..self.cfg.position_iterations) |iter| {
//         self.rebuildBroadphase();

//         const ctx = Ctx{ .world = self, .iter = iter };
//         self.spatial_hash.forEachPair(ctx, processCollisionPairIter);
//     }
// }

fn solveCollisions(self: *World) void {
    // PHASE 1: BROADPHASE
    // We do this EXACTLY ONCE.
    // We trust that bodies won't tunnel completely through objects during the sub-steps.
    // (The 'Fat AABB' or 'Contact Slop' handles small movements)
    self.spatial_hash.update(self.slots.items) catch |err| {
        std.log.err("Broadphase failed: {}", .{err});
        return;
    };

    const pairs = self.spatial_hash.pairs.items;
    self.debug_stats.collision_checks = @intCast(pairs.len);

    // PHASE 2: SOLVER LOOP
    // We iterate the resolution logic multiple times over the SAME pairs.
    for (0..self.cfg.position_iterations) |iter| {
        for (pairs) |pair| {
            const body1 = pair.a;
            const body2 = pair.b;

            // Narrowphase check
            // Note: We check collision again because position correction might have separated them
            if (checkBodiesCollision(body1, body2)) |manifold| {
                if (iter == 0) self.debug_stats.collisions_found += 1;

                self.debug_stats.max_penetration = @max(self.debug_stats.max_penetration, manifold.penetration);

                // Velocity Impulses (Once per step)
                if (iter == 0) {
                    CollisionResponse.resolveWithMaterials(
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

                // Position Correction (Every Iteration)
                if (manifold.penetration > self.cfg.contact_slop) {
                    CollisionResponse.correctPositions(body1, body2, manifold, self.cfg.baumgarte_factor);
                }
            }
        }
    }
}

fn rebuildBroadphase(self: *World) void {
    self.spatial_hash.clear();
    for (self.slots.items) |*slot| {
        if (!slot.alive) continue;
        self.spatial_hash.insert(&slot.body);
    }
}

fn processCollisionPairIter(ctx: Ctx, body1: *Body, body2: *Body) void {
    const self = ctx.world;

    // If neither is dynamic, nothing to resolve.
    if (body1.kind != .dynamic and body2.kind != .dynamic) return;

    self.debug_stats.collision_checks += 1;

    // Cheap AABB reject before narrowphase
    if (!body1.aabb().intersects(body2.aabb())) return;

    if (checkBodiesCollision(body1, body2)) |manifold| {
        self.debug_stats.collisions_found += 1;
        self.debug_stats.max_penetration = @max(self.debug_stats.max_penetration, manifold.penetration);

        // Velocity impulses once per step (iter == 0).
        if (ctx.iter == 0) {
            CollisionResponse.resolveWithMaterials(
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

        // Positional correction each iteration (if penetrated beyond slop).
        if (manifold.penetration > self.cfg.contact_slop) {
            CollisionResponse.correctPositions(body1, body2, manifold, self.cfg.baumgarte_factor);
        }
    }
}

fn applyDamping(self: *World) void {
    const lin_factor = 1.0 - self.cfg.linear_damping;
    const ang_factor = 1.0 - self.cfg.angular_damping;

    for (self.slots.items) |*slot| {
        if (!slot.alive) continue;
        const body = &slot.body;

        if (body.kind == .dynamic and !body.isSleeping()) {
            // Linear damping
            if (self.cfg.linear_damping > 0) {
                body.velocity = body.velocity.scale(lin_factor);
            }
            // Angular damping - prevents infinite spinning
            if (self.cfg.angular_damping > 0) {
                body.angular_velocity *= ang_factor;
            }

            // Clamp velocities to prevent instability
            const speed = body.velocity.length();
            if (speed > self.cfg.max_linear_velocity) {
                body.velocity = body.velocity.scale(self.cfg.max_linear_velocity / speed);
            }
            body.angular_velocity = std.math.clamp(
                body.angular_velocity,
                -self.cfg.max_angular_velocity,
                self.cfg.max_angular_velocity,
            );
        }
    }
}

fn maybeLogDebug(self: *World) void {
    if (!self.cfg.debug_logging) return;
    if (self.step_count % self.cfg.debug_log_interval != 0) return;

    log.info(
        "[Physics] step={d} active={d} sleeping={d} collisions={d}/{d} max_pen={d:.2} max_vel={d:.1}",
        .{
            self.step_count,
            self.debug_stats.active_bodies,
            self.debug_stats.sleeping_bodies,
            self.debug_stats.collisions_found,
            self.debug_stats.collision_checks,
            self.debug_stats.max_penetration,
            self.debug_stats.max_velocity,
        },
    );
}

fn updateSleepingBodies(self: *World, dt: f32) void {
    for (self.slots.items) |*slot| {
        if (!slot.alive) continue;
        const body = &slot.body;

        if (body.kind != .dynamic or body.isSleeping()) continue;

        const v = @sqrt(body.velocity.x * body.velocity.x + body.velocity.y * body.velocity.y);
        const w = @abs(body.angular_velocity);

        if (v < self.cfg.sleep_velocity_threshold and w < self.cfg.sleep_velocity_threshold) {
            body.sleep_time += dt;
            if (body.sleep_time > self.cfg.sleep_time_threshold) {
                body.putToSleep();
            }
        } else {
            body.sleep_time = 0.0;
        }
    }
}

// ============================================================================
// Body management (generational handles)
// ============================================================================

pub fn addBody(self: *World, body: Body) !BodyHandle {
    if (self.free_indices.pop()) |free_index| {
        const slot = &self.slots.items[free_index];
        slot.body = body;
        slot.alive = true;

        return BodyHandle{
            .index = free_index,
            .generation = slot.generation,
        };
    }

    const index: u32 = @intCast(self.slots.items.len);
    try self.slots.append(self.alloc, BodySlot{
        .body = body,
        .generation = 1,
        .alive = true,
    });

    return BodyHandle{ .index = index, .generation = 1 };
}

pub fn getBody(self: *World, handle: BodyHandle) ?*Body {
    if (handle.index >= self.slots.items.len) return null;

    const slot = &self.slots.items[handle.index];
    if (!slot.alive or slot.generation != handle.generation) return null;

    return &slot.body;
}

pub fn getBodyConst(self: *const World, handle: BodyHandle) ?*const Body {
    if (handle.index >= self.slots.items.len) return null;

    const slot = &self.slots.items[handle.index];
    if (!slot.alive or slot.generation != handle.generation) return null;

    return &slot.body;
}

pub fn removeBody(self: *World, handle: BodyHandle) bool {
    if (handle.index >= self.slots.items.len) return false;

    const slot = &self.slots.items[handle.index];
    if (!slot.alive or slot.generation != handle.generation) return false;

    slot.alive = false;
    slot.generation +%= 1; // invalidate old handles
    self.free_indices.append(self.alloc, handle.index) catch {};

    return true;
}

pub fn clearBodies(self: *World) void {
    for (self.slots.items) |*slot| {
        if (slot.alive) {
            slot.alive = false;
            slot.generation +%= 1;
        }
    }

    self.free_indices.clearRetainingCapacity();
    for (0..self.slots.items.len) |i| {
        self.free_indices.append(self.alloc, @intCast(i)) catch {};
    }
}

pub fn bodyCount(self: *const World) usize {
    var count: usize = 0;
    for (self.slots.items) |slot| {
        if (slot.alive) count += 1;
    }
    return count;
}

// ============================================================================
// Convenience constructors
// ============================================================================

pub fn addStaticRect(self: *World, x: f32, y: f32, w: f32, h: f32, opts: BodyOptions) !BodyHandle {
    return self.addBody(Body.initStatic(PhysicsShape.rect(w, h), Vec2.init(x, y), opts));
}

pub fn addDynamicRect(self: *World, x: f32, y: f32, w: f32, h: f32, opts: BodyOptions) !BodyHandle {
    return self.addBody(Body.initDynamic(PhysicsShape.rect(w, h), Vec2.init(x, y), opts));
}

pub fn addKinematicRect(self: *World, x: f32, y: f32, w: f32, h: f32, opts: BodyOptions) !BodyHandle {
    return self.addBody(Body.initKinematic(PhysicsShape.rect(w, h), Vec2.init(x, y), opts));
}

pub fn addStaticCircle(self: *World, x: f32, y: f32, radius: f32, opts: BodyOptions) !BodyHandle {
    return self.addBody(Body.initStatic(PhysicsShape.circ(radius), Vec2.init(x, y), opts));
}

pub fn addDynamicCircle(self: *World, x: f32, y: f32, radius: f32, opts: BodyOptions) !BodyHandle {
    return self.addBody(Body.initDynamic(PhysicsShape.circ(radius), Vec2.init(x, y), opts));
}

pub fn addKinematicCircle(self: *World, x: f32, y: f32, radius: f32, opts: BodyOptions) !BodyHandle {
    return self.addBody(Body.initKinematic(PhysicsShape.circ(radius), Vec2.init(x, y), opts));
}

// ============================================================================
// Config validation
// ============================================================================

fn validateConfig(cfg: Config) PhysicsConfigError!void {
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
