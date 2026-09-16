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
        self.acceleration = self.acceleration.add(force.scale(1.0 / self.mass));
    }
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
            var max_aabb = Vec2.init(std.math.floatMin(f32), std.math.floatMin(f32));
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
