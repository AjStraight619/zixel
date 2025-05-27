const std = @import("std");
const rl = @import("raylib");
const PhysicsShape = @import("../core/math/shapes.zig").PhysicsShape;
const Vector2 = rl.Vector2;
const Rectangle = rl.Rectangle;
const AABB = @import("../core/math/aabb.zig").AABB;

pub const StaticBodyOptions = struct {
    rotation: f32 = 0.0,
};

pub const DynamicBodyOptions = struct {
    rotation: f32 = 0.0,
    velocity: Vector2 = Vector2.zero(),
    acceleration: Vector2 = Vector2.zero(),
    angular_velocity: f32 = 0.0,
    angular_acceleration: f32 = 0.0,
    mass: f32 = 1.0,
    inertia: f32 = 1.0,
    restitution: f32 = 0.5,
    friction: f32 = 0.5,
};

pub const Body = struct {
    id: usize = 0,
    kind: union(enum) {
        Static: StaticBody,
        Dynamic: DynamicBody,
    },

    pub fn initStatic(shape: PhysicsShape, position: Vector2, opts: StaticBodyOptions) Body {
        return Body{
            .kind = .{ .Static = StaticBody.init(shape, position, opts) },
        };
    }

    pub fn initDynamic(shape: PhysicsShape, position: Vector2, opts: DynamicBodyOptions) Body {
        return Body{
            .kind = .{ .Dynamic = DynamicBody.init(shape, position, opts) },
        };
    }

    pub fn update(self: *Body, deltaTime: f32) void {
        switch (self.kind) {
            .Dynamic => |*dyn_body| dyn_body.update(deltaTime),
            .Static => |_| {},
        }
    }

    pub fn applyForce(self: *Body, force: Vector2) void {
        switch (self.kind) {
            .Dynamic => |*dyn_body| dyn_body.applyForce(force),
            .Static => |_| {},
        }
    }

    pub fn draw(self: *const Body, color: rl.Color) void {
        switch (self.kind) {
            .Dynamic => |dyn_body| dyn_body.draw(color),
            .Static => |stat_body| stat_body.draw(color),
        }
    }

    pub fn aabb(self: *const Body) AABB {
        switch (self.kind) {
            .Dynamic => |dyn_body| dyn_body.aabb(),
            .Static => |stat_body| stat_body.aabb(),
        }
    }

    pub fn isDynamic(self: Body) bool {
        return switch (self.kind) {
            .Dynamic => true,
            .Static => false,
        };
    }
};

pub const StaticBody = struct {
    shape: PhysicsShape,
    position: Vector2,
    rotation: f32 = 0.0,

    pub fn init(shape: PhysicsShape, position: Vector2, opts: StaticBodyOptions) StaticBody {
        return StaticBody{
            .shape = shape,
            .position = position,
            .rotation = opts.rotation,
        };
    }

    pub fn aabb(self: StaticBody) AABB {
        return computeAabb(self.shape, self.position, self.rotation);
    }

    pub fn draw(self: StaticBody, color: rl.Color) void {
        return drawShape(self.shape, self.position, self.rotation, color);
    }
};

pub const DynamicBody = struct {
    shape: PhysicsShape,
    position: Vector2,
    rotation: f32 = 0.0,
    velocity: Vector2 = Vector2.zero(),
    acceleration: Vector2 = Vector2.zero(),
    angular_velocity: f32 = 0.0,
    angular_acceleration: f32 = 0.0,
    mass: f32 = 1.0,
    inertia: f32 = 1.0,
    restitution: f32 = 0.5,
    friction: f32 = 0.5,

    const Self = @This();

    pub fn init(shape: PhysicsShape, position: Vector2, opts: DynamicBodyOptions) DynamicBody {
        return DynamicBody{
            .shape = shape,
            .position = position,
            .rotation = opts.rotation,
            .velocity = opts.velocity,
            .acceleration = opts.acceleration,
            .angular_velocity = opts.angular_velocity,
            .angular_acceleration = opts.angular_acceleration,
            .mass = opts.mass,
            .inertia = opts.inertia,
            .restitution = opts.restitution,
            .friction = opts.friction,
        };
    }

    pub fn aabb(self: DynamicBody) AABB {
        return computeAabb(self.shape, self.position, self.rotation);
    }

    pub fn draw(self: DynamicBody, color: rl.Color) void {
        return drawShape(self.shape, self.position, self.rotation, color);
    }

    pub fn applyForce(self: *DynamicBody, force: Vector2) void {
        self.acceleration = self.acceleration.add(force.scale(1.0 / self.mass));
    }

    pub fn update(self: *DynamicBody, deltaTime: f32) void {
        self.velocity = self.velocity.add(self.acceleration.scale(deltaTime));
        self.position = self.position.add(self.velocity.scale(deltaTime));
        self.acceleration = Vector2.zero();
    }
};

fn computeAabb(shape: PhysicsShape, position: Vector2, rotation: f32) AABB {
    switch (shape) {
        .rectangle => |rect_shape| {
            const half_w = rect_shape.width / 2.0;
            const half_h = rect_shape.height / 2.0;
            const corners = [_]Vector2{
                Vector2.init(-half_w, -half_h),
                Vector2.init(half_w, -half_h),
                Vector2.init(half_w, half_h),
                Vector2.init(-half_w, half_h),
            };
            var min_aabb = Vector2.init(std.math.floatMax(f32), std.math.floatMax(f32));
            var max_aabb = Vector2.init(std.math.floatMin(f32), std.math.floatMin(f32));
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
        .circle => |circle_shape| {
            const r = circle_shape.radius;
            return AABB.fromMinMax(
                position.subtract(Vector2.init(r, r)),
                position.add(Vector2.init(r, r)),
            );
        },
    }
}

fn drawShape(shape: PhysicsShape, position: Vector2, rotation_degrees: f32, color: rl.Color) void {
    switch (shape) {
        .rectangle => |rect_shape| {
            const dest_rect = rl.Rectangle{
                .x = position.x,
                .y = position.y,
                .width = rect_shape.width,
                .height = rect_shape.height,
            };
            const origin = Vector2{ .x = rect_shape.width / 2.0, .y = rect_shape.height / 2.0 };
            rl.drawRectanglePro(dest_rect, origin, rotation_degrees, color);
        },
        .circle => |circle_shape| {
            rl.drawCircleV(position, circle_shape.radius, color);
        },
    }
}
