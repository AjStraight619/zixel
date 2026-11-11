const std = @import("std");
const Vec2 = @import("../math/Vec2.zig");
const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
const Aabb = @import("../math/Aabb.zig");

pub const BodyKind = enum {
    static,
    kinematic,
    dynamic,
};

/// Options for creating a body (all kinds share these)
pub const BodyOptions = struct {
    rotation: f32 = 0.0,
    restitution: f32 = 0.5,
    friction: f32 = 0.5,
    velocity: Vec2 = Vec2.zero,
    mass: f32 = 1.0,
    /// If null, inertia is auto-calculated from shape and mass
    inertia: ?f32 = null,
};

/// Physics body - all common fields at top level for direct access
const Body = @This();

// Common fields - direct access!
shape: PhysicsShape,
position: Vec2,
rotation: f32 = 0.0,
friction: f32 = 0.5,
restitution: f32 = 0.5,

// What kind of body this is
kind: BodyKind,

// Dynamic-only data (only meaningful when kind == .dynamic)
velocity: Vec2 = Vec2.zero,
acceleration: Vec2 = Vec2.zero,
angular_velocity: f32 = 0.0,
angular_acceleration: f32 = 0.0,
mass: f32 = 1.0,
inertia: f32 = 1.0,
is_sleeping: bool = false,
sleep_time: f32 = 0.0,
/// Solver scratch, rewritten every physics step: whether something that is
/// itself at rest holds this body up against gravity.
has_support: bool = false,

// --- Constructors ---

pub fn initStatic(shape: PhysicsShape, position: Vec2, opts: BodyOptions) Body {
    return .{
        .kind = .static,
        .shape = shape,
        .position = position,
        .rotation = opts.rotation,
        .restitution = opts.restitution,
        .friction = opts.friction,
    };
}

pub fn initKinematic(shape: PhysicsShape, position: Vec2, opts: BodyOptions) Body {
    return .{
        .kind = .kinematic,
        .shape = shape,
        .position = position,
        .rotation = opts.rotation,
        .restitution = opts.restitution,
        .friction = opts.friction,
        .velocity = opts.velocity,
    };
}

pub fn initDynamic(shape: PhysicsShape, position: Vec2, opts: BodyOptions) Body {
    // Auto-calculate inertia from shape and mass if not specified
    const inertia = opts.inertia orelse computeInertia(shape, opts.mass);

    return .{
        .kind = .dynamic,
        .shape = shape,
        .position = position,
        .rotation = opts.rotation,
        .restitution = opts.restitution,
        .friction = opts.friction,
        .velocity = opts.velocity,
        .mass = opts.mass,
        .inertia = inertia,
    };
}

/// Compute moment of inertia for a shape with given mass
/// Rectangle: I = (1/12) * m * (w^2 + h^2)
/// Circle:    I = (1/2) * m * r^2
fn computeInertia(shape: PhysicsShape, mass: f32) f32 {
    return switch (shape) {
        .rectangle => |r| (1.0 / 12.0) * mass * (r.width * r.width + r.height * r.height),
        .circle => |c| 0.5 * mass * c.radius * c.radius,
    };
}

pub fn applyForce(self: *Body, force: Vec2) void {
    if (self.kind == .dynamic) {
        if (force.x != 0 or force.y != 0) self.wakeUp();
        self.acceleration = self.acceleration.add(force.scale(self.invMass()));
    }
}

/// Inverse mass used by the solver. Static and kinematic bodies, and dynamic
/// bodies with a non-positive or non-finite mass, behave as infinitely heavy
/// instead of turning velocities into NaN.
pub fn invMass(self: *const Body) f32 {
    return if (self.kind == .dynamic) safeInverse(self.mass) else 0.0;
}

/// Inverse moment of inertia, with the same rules as `invMass`.
pub fn invInertia(self: *const Body) f32 {
    return if (self.kind == .dynamic) safeInverse(self.inertia) else 0.0;
}

fn safeInverse(value: f32) f32 {
    return if (value > 0 and std.math.isFinite(value)) 1.0 / value else 0.0;
}

pub fn aabb(self: *const Body) Aabb {
    return computeAabb(self.shape, self.position, self.rotation);
}

pub fn isSleeping(self: *const Body) bool {
    return self.kind == .dynamic and self.is_sleeping;
}

pub fn wakeUp(self: *Body) void {
    if (self.kind == .dynamic) {
        self.is_sleeping = false;
        self.sleep_time = 0.0;
    }
}

pub fn putToSleep(self: *Body) void {
    if (self.kind == .dynamic) {
        self.is_sleeping = true;
        self.velocity = Vec2.zero;
        self.angular_velocity = 0.0;
    }
}

/// Compute Aabb for a shape at a given position and rotation
fn computeAabb(shape: PhysicsShape, position: Vec2, rotation: f32) Aabb {
    switch (shape) {
        .rectangle => |rect| {
            const half_w = rect.width / 2.0;
            const half_h = rect.height / 2.0;
            const corners = [_]Vec2{
                Vec2.init(-half_w, -half_h),
                Vec2.init(half_w, -half_h),
                Vec2.init(half_w, half_h),
                Vec2.init(-half_w, half_h),
            };
            var min_aabb = Vec2.init(std.math.floatMax(f32), std.math.floatMax(f32));
            var max_aabb = Vec2.init(-std.math.floatMax(f32), -std.math.floatMax(f32));
            for (corners) |corner| {
                const rotated = corner.rotate(rotation);
                const world = rotated.add(position);
                min_aabb.x = @min(min_aabb.x, world.x);
                min_aabb.y = @min(min_aabb.y, world.y);
                max_aabb.x = @max(max_aabb.x, world.x);
                max_aabb.y = @max(max_aabb.y, world.y);
            }
            return Aabb.fromMinMax(min_aabb, max_aabb);
        },
        .circle => |circle| {
            const r = circle.radius;
            return Aabb.fromMinMax(
                position.subtract(Vec2.init(r, r)),
                position.add(Vec2.init(r, r)),
            );
        },
    }
}

test "rotated rectangle bounds match analytic extents across the origin" {
    var rng = std.Random.DefaultPrng.init(73);
    const random = rng.random();
    for (0..1000) |_| {
        const width = 3 + random.float(f32) * 80;
        const height = 3 + random.float(f32) * 80;
        const position = Vec2.init(random.float(f32) * 1000 - 500, random.float(f32) * 1000 - 500);
        const rotation = random.float(f32) * 2 * std.math.pi;
        const body = Body.initDynamic(PhysicsShape.rect(width, height), position, .{ .rotation = rotation });
        const half = Vec2.init(
            @abs(@cos(rotation)) * width / 2 + @abs(@sin(rotation)) * height / 2,
            @abs(@sin(rotation)) * width / 2 + @abs(@cos(rotation)) * height / 2,
        );
        const expected = Aabb.fromCenterHalfExtents(position, half);
        const actual = body.aabb();
        try std.testing.expectApproxEqAbs(expected.min.x, actual.min.x, 0.0001);
        try std.testing.expectApproxEqAbs(expected.min.y, actual.min.y, 0.0001);
        try std.testing.expectApproxEqAbs(expected.max.x, actual.max.x, 0.0001);
        try std.testing.expectApproxEqAbs(expected.max.y, actual.max.y, 0.0001);
    }
}

test "nonzero force wakes a sleeping dynamic body and resets its sleep timer" {
    var body = Body.initDynamic(PhysicsShape.circ(1), Vec2.zero, .{ .mass = 2 });
    body.sleep_time = 10;
    body.putToSleep();
    body.applyForce(.{ .x = 0, .y = 6 });
    try std.testing.expect(!body.isSleeping());
    try std.testing.expectEqual(@as(f32, 0), body.sleep_time);
    try std.testing.expectEqual(@as(f32, 3), body.acceleration.y);
}

test "non-positive mass and inertia act as infinite instead of producing NaN" {
    var body = Body.initDynamic(PhysicsShape.circ(0), Vec2.zero, .{ .mass = 0 });
    try std.testing.expectEqual(@as(f32, 0), body.invMass());
    try std.testing.expectEqual(@as(f32, 0), body.invInertia());
    body.applyForce(.{ .x = 5, .y = 5 });
    try std.testing.expectEqual(Vec2.zero, body.acceleration);
    body.mass = -3;
    try std.testing.expectEqual(@as(f32, 0), body.invMass());
    body.mass = 4;
    try std.testing.expectEqual(@as(f32, 0.25), body.invMass());
}

test "zero force preserves sleep and forces do not affect infinite-mass bodies" {
    var body = Body.initDynamic(PhysicsShape.circ(1), Vec2.zero, .{});
    body.putToSleep();
    body.applyForce(Vec2.zero);
    try std.testing.expect(body.isSleeping());
    var stationary = Body.initStatic(PhysicsShape.circ(1), Vec2.zero, .{});
    var kinematic = Body.initKinematic(PhysicsShape.circ(1), Vec2.zero, .{});
    for ([_]*Body{ &stationary, &kinematic }) |other| {
        other.applyForce(.{ .x = 4, .y = 6 });
        try std.testing.expectEqual(Vec2.zero, other.acceleration);
    }
}
