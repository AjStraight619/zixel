const std = @import("std");
const Vec2 = @import("../math/vec2.zig");
const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
const AABB = @import("../math/aabb.zig");

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
    inertia: f32 = 1.0,
};

/// Physics body - all common fields at top level for direct access
pub const Body = struct {
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
        return .{
            .kind = .dynamic,
            .shape = shape,
            .position = position,
            .rotation = opts.rotation,
            .restitution = opts.restitution,
            .friction = opts.friction,
            .velocity = opts.velocity,
            .mass = opts.mass,
            .inertia = opts.inertia,
        };
    }

    pub fn applyForce(self: *Body, force: Vec2) void {
        if (self.kind == .dynamic) {
            self.acceleration = self.acceleration.add(force.scale(1.0 / self.mass));
        }
    }

    pub fn aabb(self: *const Body) AABB {
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
};

/// Compute AABB for a shape at a given position and rotation
fn computeAabb(shape: PhysicsShape, position: Vec2, rotation: f32) AABB {
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
            return AABB.fromMinMax(min_aabb, max_aabb);
        },
        .circle => |circle| {
            const r = circle.radius;
            return AABB.fromMinMax(
                position.subtract(Vec2.init(r, r)),
                position.add(Vec2.init(r, r)),
            );
        },
    }
}
