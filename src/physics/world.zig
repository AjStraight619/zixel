const std = @import("std");
const log = std.log;

const Vec2 = @import("../math/vec2.zig");
const body_mod = @import("body.zig");
const Body = body_mod.Body;
const BodyOptions = body_mod.BodyOptions;
const BodyKind = body_mod.BodyKind;

const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;

const Allocator = std.mem.Allocator;

const narrowphase = @import("narrowphase.zig");
const checkBodiesCollision = narrowphase.NarrowPhase.checkBodiesCollision;

const CollisionResponse = @import("response.zig");

const entity_mod = @import("../engine/Entity.zig");
pub const Entity = entity_mod.Entity;
pub const EntityDef = entity_mod.EntityDef;
pub const EntityHandle = entity_mod.EntityHandle;

const Renderer = @import("../engine/Renderer.zig");
const Color = Renderer.Color;

const SpatialHash = @import("broadphase.zig").SpatialHash;

pub const Config = struct {
    gravity: Vec2 = Vec2{ .x = 0, .y = 980 },
    position_iterations: u32 = 8,
    velocity_iterations: u32 = 8,
    physics_time_step: f32 = 1.0 / 60.0,
    max_delta_time: f32 = 1.0 / 30.0,
    allow_sleeping: bool = true,
    sleep_time_threshold: f32 = 0.3,
    sleep_velocity_threshold: f32 = 25.0,
    contact_slop: f32 = 0.3,
    baumgarte_factor: f32 = 0.5,
    restitution_clamp_threshold: f32 = 3.0,
    linear_damping: f32 = 0.002,
    angular_damping: f32 = 0.05,
    max_linear_velocity: f32 = 2000.0,
    max_angular_velocity: f32 = 20.0,
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
pub const EntitySlot = struct {
    entity: Entity,
    generation: u32 = 1,
    alive: bool = false,
};

// Legacy alias for backwards compatibility
pub const BodySlot = EntitySlot;

pub const DebugStats = struct {
    active_bodies: u32 = 0,
    sleeping_bodies: u32 = 0,
    collision_checks: u32 = 0,
    collisions_found: u32 = 0,
    max_penetration: f32 = 0,
    max_velocity: f32 = 0,
};

alloc: Allocator,
slots: std.ArrayList(EntitySlot),
free_indices: std.ArrayList(u32),
name_index: std.StringHashMap(EntityHandle),
spatial_hash: SpatialHash,
cfg: Config,
accumulated_time: f32 = 0.0,
step_count: u64 = 0,
debug_stats: DebugStats = .{},

pub fn init(alloc: Allocator, cfg: Config) PhysicsConfigError!World {
    try validateConfig(cfg);
    return .{
        .alloc = alloc,
        .slots = .empty,
        .free_indices = .empty,
        .name_index = std.StringHashMap(EntityHandle).init(alloc),
        .spatial_hash = SpatialHash.init(alloc, 64.0),
        .cfg = cfg,
    };
}

pub fn deinit(self: *World) void {
    self.name_index.deinit();
    self.spatial_hash.deinit();
    self.slots.deinit(self.alloc);
    self.free_indices.deinit(self.alloc);
}

/// Spawn an entity from a definition
pub fn spawn(self: *World, def: EntityDef) !EntityHandle {
    const body = if (def.body) |b| blk: {
        const opts = BodyOptions{
            .rotation = def.rotation,
            .restitution = b.restitution,
            .friction = b.friction,
            .velocity = b.velocity,
            .mass = b.mass,
            .inertia = b.inertia,
        };
        break :blk switch (b.kind) {
            .static => Body.initStatic(b.shape, def.position, opts),
            .dynamic => Body.initDynamic(b.shape, def.position, opts),
            .kinematic => Body.initKinematic(b.shape, def.position, opts),
        };
    } else Body.initStatic(PhysicsShape.rect(1, 1), def.position, .{});

    const entity = Entity{
        .name = def.name,
        .tags = def.tags,
        .owner = def.owner,
        .body = body,
        .sprite = def.sprite,
    };

    // Insert into slot storage
    const handle = try self.insertEntity(entity);

    // Index by name for fast lookup
    if (def.name) |n| {
        try self.name_index.put(n, handle);
    }

    return handle;
}

/// Get entity by name
pub fn getByName(self: *World, name: []const u8) ?*Entity {
    if (self.name_index.get(name)) |handle| {
        return self.get(handle);
    }
    return null;
}

/// Get entity by handle
pub fn get(self: *World, handle: EntityHandle) ?*Entity {
    if (handle.index >= self.slots.items.len) return null;
    const slot = &self.slots.items[handle.index];
    if (!slot.alive or slot.generation != handle.generation) return null;
    return &slot.entity;
}

/// Get entity by handle (const version)
pub fn getConst(self: *const World, handle: EntityHandle) ?*const Entity {
    if (handle.index >= self.slots.items.len) return null;
    const slot = &self.slots.items[handle.index];
    if (!slot.alive or slot.generation != handle.generation) return null;
    return &slot.entity;
}

/// Remove all entities owned by a specific scene
pub fn removeByOwner(self: *World, owner: Entity.Owner) void {
    for (self.slots.items, 0..) |*slot, i| {
        if (!slot.alive) continue;

        const matches = switch (owner) {
            .none => slot.entity.owner == .none,
            .scene => |scene_name| switch (slot.entity.owner) {
                .scene => |s| std.mem.eql(u8, s, scene_name),
                .none => false,
            },
        };

        if (matches) {
            // Remove from name index
            if (slot.entity.name) |name| {
                _ = self.name_index.remove(name);
            }
            slot.alive = false;
            slot.generation +%= 1;
            self.free_indices.append(self.alloc, @intCast(i)) catch {};
        }
    }
}

/// Clear all entities (except persistent ones if keep_persistent is true)
pub fn clearAll(self: *World, keep_persistent: bool) void {
    for (self.slots.items, 0..) |*slot, i| {
        if (!slot.alive) continue;

        if (keep_persistent and slot.entity.owner == .none) continue;

        if (slot.entity.name) |n| {
            _ = self.name_index.remove(n);
        }
        slot.alive = false;
        slot.generation +%= 1;
        self.free_indices.append(self.alloc, @intCast(i)) catch {};
    }
}

/// Render all entities that have sprites
pub fn renderAll(self: *World, renderer: *Renderer) void {
    for (self.slots.items) |*slot| {
        if (!slot.alive) continue;
        if (slot.entity.sprite) |sprite| {
            const body = &slot.entity.body;
            switch (body.shape) {
                .circle => |c| {
                    renderer.drawCircle(body.position.x, body.position.y, c.radius, sprite.color);
                },
                .rectangle => |r| {
                    renderer.drawRotatedRect(body.position.x, body.position.y, r.width, r.height, body.rotation, sprite.color);
                },
            }
        }
    }
}

/// Count entities
pub fn entityCount(self: *const World) usize {
    var count: usize = 0;
    for (self.slots.items) |slot| {
        if (slot.alive) count += 1;
    }
    return count;
}

// ============================================================================
// Physics update (works on entity.body)
// ============================================================================

pub fn update(self: *World, delta_time: f32) void {
    const clamped_dt = @min(delta_time, self.cfg.max_delta_time);
    self.accumulated_time += clamped_dt;

    while (self.accumulated_time >= self.cfg.physics_time_step) {
        self.stepPhysics(self.cfg.physics_time_step);
        self.accumulated_time -= self.cfg.physics_time_step;
        self.step_count += 1;
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
        const body = &slot.entity.body;

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

        body.applyForce(Vec2{
            .x = self.cfg.gravity.x * body.mass,
            .y = self.cfg.gravity.y * body.mass,
        });

        body.velocity = body.velocity.add(body.acceleration.scale(dt));
        body.acceleration = Vec2.zero;
        body.angular_velocity += body.angular_acceleration * dt;
        body.angular_acceleration = 0.0;
    }
}

fn integratePositions(self: *World, dt: f32) void {
    for (self.slots.items) |*slot| {
        if (!slot.alive) continue;
        const body = &slot.entity.body;

        switch (body.kind) {
            .dynamic => {
                if (body.isSleeping()) continue;
                body.position = body.position.add(body.velocity.scale(dt));
                body.rotation += body.angular_velocity * dt;
                body.rotation = std.math.wrap(body.rotation, std.math.pi);
            },
            .kinematic => {
                body.position = body.position.add(body.velocity.scale(dt));
            },
            .static => {},
        }
    }
}

fn solveCollisions(self: *World) void {
    // Build pairs from entity bodies
    self.spatial_hash.updateFromEntities(self.slots.items) catch |err| {
        log.err("Broadphase failed: {}", .{err});
        return;
    };

    const pairs = self.spatial_hash.pairs.items;
    self.debug_stats.collision_checks = @intCast(pairs.len);

    for (0..self.cfg.position_iterations) |iter| {
        for (pairs) |pair| {
            const body1 = pair.a;
            const body2 = pair.b;

            if (checkBodiesCollision(body1, body2)) |manifold| {
                if (iter == 0) self.debug_stats.collisions_found += 1;
                self.debug_stats.max_penetration = @max(self.debug_stats.max_penetration, manifold.penetration);

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

                if (manifold.penetration > self.cfg.contact_slop) {
                    CollisionResponse.correctPositions(body1, body2, manifold, self.cfg.baumgarte_factor);
                }
            }
        }
    }
}

fn applyDamping(self: *World) void {
    const lin_factor = 1.0 - self.cfg.linear_damping;
    const ang_factor = 1.0 - self.cfg.angular_damping;

    for (self.slots.items) |*slot| {
        if (!slot.alive) continue;
        const body = &slot.entity.body;

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

fn updateSleepingBodies(self: *World, dt: f32) void {
    for (self.slots.items) |*slot| {
        if (!slot.alive) continue;
        const body = &slot.entity.body;

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

fn insertEntity(self: *World, entity: Entity) !EntityHandle {
    if (self.free_indices.pop()) |free_index| {
        const slot = &self.slots.items[free_index];
        slot.entity = entity;
        slot.alive = true;
        return EntityHandle{ .index = free_index, .generation = slot.generation };
    }

    const index: u32 = @intCast(self.slots.items.len);
    try self.slots.append(self.alloc, EntitySlot{
        .entity = entity,
        .generation = 1,
        .alive = true,
    });

    return EntityHandle{ .index = index, .generation = 1 };
}

// ============================================================================
// Legacy body API (for compatibility - wraps entity API)
// ============================================================================

pub const BodyHandle = @import("handle.zig").BodyHandle;

/// Legacy: add a raw body (creates entity with no name/sprite)
pub fn addBody(self: *World, body: Body) !EntityHandle {
    return self.insertEntity(Entity{ .body = body });
}

/// Legacy: get body by handle
pub fn getBody(self: *World, handle: EntityHandle) ?*Body {
    if (self.get(handle)) |entity| {
        return &entity.body;
    }
    return null;
}

/// Legacy: clear all bodies
pub fn clearBodies(self: *World) void {
    self.clearAll(false);
}

/// Legacy convenience constructors
pub fn addStaticRect(self: *World, x: f32, y: f32, w: f32, h: f32, opts: BodyOptions) !EntityHandle {
    return self.addBody(Body.initStatic(PhysicsShape.rect(w, h), Vec2.init(x, y), opts));
}

pub fn addDynamicRect(self: *World, x: f32, y: f32, w: f32, h: f32, opts: BodyOptions) !EntityHandle {
    return self.addBody(Body.initDynamic(PhysicsShape.rect(w, h), Vec2.init(x, y), opts));
}

pub fn addKinematicRect(self: *World, x: f32, y: f32, w: f32, h: f32, opts: BodyOptions) !EntityHandle {
    return self.addBody(Body.initKinematic(PhysicsShape.rect(w, h), Vec2.init(x, y), opts));
}

pub fn addStaticCircle(self: *World, x: f32, y: f32, radius: f32, opts: BodyOptions) !EntityHandle {
    return self.addBody(Body.initStatic(PhysicsShape.circ(radius), Vec2.init(x, y), opts));
}

pub fn addDynamicCircle(self: *World, x: f32, y: f32, radius: f32, opts: BodyOptions) !EntityHandle {
    return self.addBody(Body.initDynamic(PhysicsShape.circ(radius), Vec2.init(x, y), opts));
}

pub fn addKinematicCircle(self: *World, x: f32, y: f32, radius: f32, opts: BodyOptions) !EntityHandle {
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
    if (cfg.baumgarte_factor < 0) {
        log.err("baumgarte_factor must be >= 0 (got {})", .{cfg.baumgarte_factor});
        return PhysicsConfigError.NegativeBaumgarte;
    }
    if (cfg.restitution_clamp_threshold < 0) {
        log.err("restitution_clamp_threshold must be >= 0 (got {})", .{cfg.restitution_clamp_threshold});
        return PhysicsConfigError.NegativeRestitutionClamp;
    }
}
