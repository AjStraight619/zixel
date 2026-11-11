//! Physics simulation independent of entity storage and rendering.
const std = @import("std");
const log = std.log.scoped(.zixel_physics);
const Allocator = std.mem.Allocator;
const Vec2 = @import("../math/Vec2.zig");
const SpatialHash = @import("broadphase.zig").SpatialHash;
const narrowphase = @import("narrowphase.zig");
const checkBodiesCollision = narrowphase.checkBodiesCollision;
const Body = @import("Body.zig");
const response = @import("response.zig");
const Physics = @This();

pub const Config = struct {
    gravity: Vec2 = Vec2{ .x = 0, .y = 980 },
    position_iterations: u32 = 8,
    velocity_iterations: u32 = 8,
    physics_time_step: f32 = 1.0 / 60.0,
    max_delta_time: f32 = 1.0 / 30.0,
    allow_sleeping: bool = true,
    sleep_time_threshold: f32 = 0.3,
    /// Linear speed (world units/s) below which a body may fall asleep.
    sleep_velocity_threshold: f32 = 25.0,
    /// Spin (rad/s) below which a body may fall asleep.
    sleep_angular_velocity_threshold: f32 = 0.5,
    contact_slop: f32 = 0.3,
    baumgarte_factor: f32 = 0.5,
    restitution_clamp_threshold: f32 = 3.0,
    linear_damping: f32 = 0.002,
    angular_damping: f32 = 0.05,
    max_linear_velocity: f32 = 2000.0,
    max_angular_velocity: f32 = 20.0,
    /// Interval in physics steps for scoped debug statistics; zero disables them.
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

pub const DebugStats = struct {
    active_bodies: u32 = 0,
    sleeping_bodies: u32 = 0,
    collision_checks: u32 = 0,
    collisions_found: u32 = 0,
    max_penetration: f32 = 0,
    max_velocity: f32 = 0,
};

spatial_hash: SpatialHash,
cfg: Config,
accumulated_time: f32 = 0,
step_count: u64 = 0,
debug_stats: DebugStats = .{},

pub fn init(alloc: Allocator, cfg: Config) PhysicsConfigError!Physics {
    try validateConfig(cfg);
    return .{ .spatial_hash = SpatialHash.init(alloc, 64), .cfg = cfg };
}

pub fn deinit(self: *Physics) void {
    self.spatial_hash.deinit();
}

/// Accepts a copyable iterator with next() ?*Body. Body storage must remain
/// stable throughout this call; construct a fresh iterator for each update.
pub fn update(self: *Physics, bodies: anytype, delta_time: f32) void {
    const clamped_dt = @min(delta_time, self.cfg.max_delta_time);
    self.accumulated_time += clamped_dt;

    while (self.accumulated_time >= self.cfg.physics_time_step) {
        self.stepPhysics(bodies, self.cfg.physics_time_step);
        self.accumulated_time -= self.cfg.physics_time_step;
        self.step_count += 1;
    }
}

fn stepPhysics(self: *Physics, bodies: anytype, dt: f32) void {
    self.debug_stats = .{};

    if (self.cfg.allow_sleeping) {
        self.updateSleepingBodies(bodies, dt);
    }

    self.integrateVelocities(bodies, dt);
    self.integratePositions(bodies, dt);
    self.solveCollisions(bodies);
    self.applyDamping(bodies);
    self.maybeLogDebug();
}

fn integrateVelocities(self: *Physics, bodies: anytype, dt: f32) void {
    var iter = bodies;
    while (iter.next()) |body| {
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

        // Gravity affects awake bodies without resetting their sleep timers.
        // Explicit forces use Body.applyForce to wake the body instead.
        body.acceleration = body.acceleration.add(self.cfg.gravity);

        body.velocity = body.velocity.add(body.acceleration.scale(dt));
        body.acceleration = Vec2.zero;
        body.angular_velocity += body.angular_acceleration * dt;
        body.angular_acceleration = 0.0;
    }
}

fn integratePositions(_: *Physics, bodies: anytype, dt: f32) void {
    var iter = bodies;
    while (iter.next()) |body| {
        switch (body.kind) {
            .dynamic => {
                if (body.isSleeping()) continue;
                body.position = body.position.add(body.velocity.scale(dt));
                body.rotation += body.angular_velocity * dt;
                body.rotation = std.math.wrap(body.rotation, std.math.pi);
            },
            .kinematic => {
                body.position = body.position.add(body.velocity.scale(dt));
                body.rotation += body.angular_velocity * dt;
                body.rotation = std.math.wrap(body.rotation, std.math.pi);
            },
            .static => {},
        }
    }
}

/// How far past the contact slop a resting body is probed along gravity when
/// it has no overlapping contact (bodies corrected to exactly touching).
const support_probe_margin: f32 = 0.1;

fn gravityDirection(self: *const Physics) ?Vec2 {
    const len = self.cfg.gravity.length();
    return if (len > 0) self.cfg.gravity.scale(1.0 / len) else null;
}

/// Something at rest: a body resting on it may sleep, and stays asleep.
fn isStableSupport(body: *const Body) bool {
    return switch (body.kind) {
        .static => true,
        .kinematic => body.velocity.x == 0 and body.velocity.y == 0 and body.angular_velocity == 0,
        .dynamic => body.isSleeping(),
    };
}

/// Marks `body` as supported when `other` is at rest and lies below it along
/// gravity. `normal` is the contact normal pointing from `body` to `other`, if
/// the two currently overlap.
fn noteSupport(self: *const Physics, body: *Body, other: *const Body, normal: ?Vec2, down: Vec2) void {
    if (body.kind != .dynamic or body.has_support or !isStableSupport(other)) return;

    const toward_other = normal orelse blk: {
        // Only bodies that are asleep or settling pay for the extra probe.
        if (!body.isSleeping() and body.sleep_time <= 0) return;
        const offset = down.scale(self.cfg.contact_slop + support_probe_margin);
        const probe = narrowphase.checkShapesCollision(
            body.shape,
            body.position.add(offset),
            body.rotation,
            other.shape,
            other.position,
            other.rotation,
        ) orelse return;
        break :blk probe.normal;
    };

    if (toward_other.dot(down) > 0) body.has_support = true;
}

fn solveCollisions(self: *Physics, bodies: anytype) void {
    // Build pairs from entity bodies
    self.spatial_hash.update(bodies) catch |err| {
        log.err("Broadphase failed: {}", .{err});
        return;
    };

    var reset_iter = bodies;
    while (reset_iter.next()) |body| body.has_support = false;
    const down = self.gravityDirection();

    const pairs = self.spatial_hash.pairs.items;
    self.debug_stats.collision_checks = @intCast(pairs.len);

    for (0..self.cfg.position_iterations) |iter| {
        for (pairs) |pair| {
            const body1 = pair.a;
            const body2 = pair.b;
            const contact = checkBodiesCollision(body1, body2);

            if (iter == 0) {
                if (down) |dir| {
                    self.noteSupport(body1, body2, if (contact) |m| m.normal else null, dir);
                    self.noteSupport(body2, body1, if (contact) |m| m.normal.negate() else null, dir);
                }
            }

            if (contact) |manifold| {
                if (iter == 0) self.debug_stats.collisions_found += 1;
                self.debug_stats.max_penetration = @max(self.debug_stats.max_penetration, manifold.penetration);

                if (iter == 0) {
                    response.resolveWithMaterials(
                        body1,
                        body2,
                        manifold,
                        body1.restitution,
                        body2.restitution,
                        body1.friction,
                        body2.friction,
                        self.cfg.restitution_clamp_threshold,
                        .{ .down = down, .wake_speed = self.cfg.sleep_velocity_threshold },
                    );
                }

                if (manifold.penetration > self.cfg.contact_slop) {
                    response.correctPositions(body1, body2, manifold, self.cfg.baumgarte_factor);
                }
            }
        }
    }

    // A sleeping body whose support moved away, started moving, or was removed
    // has nothing holding it up any more: let gravity act on it again.
    if (down != null) {
        var wake_iter = bodies;
        while (wake_iter.next()) |body| {
            if (body.isSleeping() and !body.has_support) body.wakeUp();
        }
    }
}

fn applyDamping(self: *Physics, bodies: anytype) void {
    const lin_factor = 1.0 - self.cfg.linear_damping;
    const ang_factor = 1.0 - self.cfg.angular_damping;

    var iter = bodies;
    while (iter.next()) |body| {
        if (body.kind == .dynamic and !body.isSleeping()) {
            if (self.cfg.linear_damping > 0) {
                body.velocity = body.velocity.scale(lin_factor);
            }
            if (self.cfg.angular_damping > 0) {
                body.angular_velocity *= ang_factor;
            }

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

fn updateSleepingBodies(self: *Physics, bodies: anytype, dt: f32) void {
    // Under gravity only bodies resting on something at rest may sleep; this
    // uses the support found by the previous step's collision pass.
    const needs_support = self.gravityDirection() != null;
    var iter = bodies;
    while (iter.next()) |body| {
        if (body.kind != .dynamic or body.isSleeping()) continue;

        // Integrate pending forces before considering the body for sleep, even
        // when the sleep threshold is shorter than a single physics step.
        if (body.acceleration.x != 0 or body.acceleration.y != 0 or body.angular_acceleration != 0) {
            body.sleep_time = 0;
            continue;
        }

        const v = @sqrt(body.velocity.x * body.velocity.x + body.velocity.y * body.velocity.y);
        const w = @abs(body.angular_velocity);

        if (v < self.cfg.sleep_velocity_threshold and w < self.cfg.sleep_angular_velocity_threshold) {
            body.sleep_time += dt;
            if (body.sleep_time > self.cfg.sleep_time_threshold and (!needs_support or body.has_support)) {
                body.putToSleep();
            }
        } else {
            body.sleep_time = 0.0;
        }
    }
}

fn maybeLogDebug(self: *Physics) void {
    if (self.cfg.debug_log_interval == 0 or self.step_count % self.cfg.debug_log_interval != 0) return;

    log.debug(
        "step={d} active={d} sleeping={d} collisions={d}/{d} max_pen={d:.2} max_vel={d:.1}",
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
        log.err("max_delta_time ({}) must be >= physics_time_step ({})", .{ cfg.max_delta_time, cfg.physics_time_step });
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
    if (cfg.sleep_angular_velocity_threshold < 0) {
        log.err("sleep_angular_velocity_threshold must be >= 0 (got {})", .{cfg.sleep_angular_velocity_threshold});
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
