const std = @import("std");
const rl = @import("raylib");
const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
const Vector2 = rl.Vector2;
const Rectangle = rl.Rectangle;
const AABB = @import("../math/aabb.zig").AABB;

pub const StaticBodyOptions = struct {
    rotation: f32 = 0.0,
    restitution: f32 = 0.5, // How bouncy the static surface is
    friction: f32 = 0.7, // Surface friction (higher = more grip)
};

pub const DynamicBodyOptions = struct {
    rotation: f32 = 0.0,
    velocity: Vector2 = Vector2{ .x = 0.0, .y = 0.0 },
    acceleration: Vector2 = Vector2{ .x = 0.0, .y = 0.0 },
    angular_velocity: f32 = 0.0,
    angular_acceleration: f32 = 0.0,
    mass: f32 = 1.0,
    inertia: f32 = 1.0,
    restitution: f32 = 0.5,
    friction: f32 = 0.5,
};

pub const KinematicBodyOptions = struct {
    velocity: Vector2 = Vector2{ .x = 0.0, .y = 0.0 },
    restitution: f32 = 0.0,
    friction: f32 = 0.0,
    rotation: f32 = 0.0,
};

pub const Body = struct {
    id: usize = 0, // Tracks body and links to scene data/rendering
    kind: union(enum) {
        static: StaticBody,
        dynamic: DynamicBody,
        kinematic: KinematicBody,
    },

    pub fn initStatic(shape: PhysicsShape, position: Vector2, opts: StaticBodyOptions) Body {
        return Body{
            .kind = .{ .static = StaticBody.init(shape, position, opts) },
        };
    }

    pub fn initDynamic(shape: PhysicsShape, position: Vector2, opts: DynamicBodyOptions) Body {
        return Body{
            .kind = .{ .dynamic = DynamicBody.init(shape, position, opts) },
        };
    }

    pub fn initKinematic(shape: PhysicsShape, position: Vector2, opts: KinematicBodyOptions) Body {
        return Body{
            .kind = .{ .kinematic = KinematicBody.init(shape, position, opts) },
        };
    }

    pub fn update(self: *Body, deltaTime: f32) void {
        switch (self.kind) {
            .dynamic => |*dyn_body| dyn_body.update(deltaTime),
            .kinematic => |*kin_body| kin_body.update(deltaTime),
            .static => |_| {},
        }
    }

    pub fn applyForce(self: *Body, force: Vector2) void {
        switch (self.kind) {
            .dynamic => |*dyn_body| dyn_body.applyForce(force),
            .kinematic => |_| {}, // Kinematic bodies ignore forces
            .static => |_| {},
        }
    }

    pub fn draw(self: *const Body, color: rl.Color) void {
        switch (self.kind) {
            .dynamic => |dyn_body| dyn_body.draw(color),
            .kinematic => |kin_body| kin_body.draw(color),
            .static => |stat_body| stat_body.draw(color),
        }
    }

    pub fn aabb(self: *const Body) AABB {
        return switch (self.kind) {
            .dynamic => |dyn_body| dyn_body.aabb(),
            .kinematic => |kin_body| kin_body.aabb(),
            .static => |stat_body| stat_body.aabb(),
        };
    }

    /// Generic field accessor using comptime to reduce repetitive switch statements
    fn getField(self: *const Body, comptime field_name: []const u8) @TypeOf(@field(@field(self.kind, "dynamic"), field_name)) {
        return switch (self.kind) {
            inline else => |body| @field(body, field_name),
        };
    }

    pub fn getShape(self: *const Body) PhysicsShape {
        return self.getField("shape");
    }

    pub fn getPosition(self: *const Body) Vector2 {
        return self.getField("position");
    }

    pub fn getRotation(self: *const Body) f32 {
        return self.getField("rotation");
    }

    /// Get the restitution (bounciness) of this body
    pub fn getRestitution(self: *const Body) f32 {
        return self.getField("restitution");
    }

    /// Get the friction of this body
    pub fn getFriction(self: *const Body) f32 {
        return self.getField("friction");
    }

    // Sleep management
    pub fn isSleeping(self: *const Body) bool {
        return switch (self.kind) {
            .dynamic => |dyn_body| dyn_body.is_sleeping,
            .kinematic => false, // Kinematic bodies don't sleep
            .static => false, // Static bodies are never considered "sleeping"
        };
    }

    pub fn wakeUp(self: *Body) void {
        switch (self.kind) {
            .dynamic => |*dyn_body| {
                // Add debug logging for ball (ID 1)
                if (self.id == 1) {
                    std.debug.print("SLEEP DEBUG: WAKE UP CALLED! Body ID {}, sleep_time was {d:.3}, resetting to 0.0\n", .{ self.id, dyn_body.sleep_time });
                }
                dyn_body.is_sleeping = false;
                dyn_body.sleep_time = 0.0;
            },
            .kinematic => {}, // Kinematic bodies don't need waking
            .static => {}, // Static bodies don't need waking
        }
    }

    pub fn putToSleep(self: *Body) void {
        switch (self.kind) {
            .dynamic => |*dyn_body| {
                dyn_body.is_sleeping = true;
                dyn_body.velocity = Vector2{ .x = 0.0, .y = 0.0 };
                dyn_body.angular_velocity = 0.0;
            },
            .kinematic => {}, // Kinematic bodies don't sleep
            .static => {}, // Static bodies don't sleep
        }
    }

    pub fn getVelocity(self: *const Body) Vector2 {
        return switch (self.kind) {
            .dynamic => |dyn_body| dyn_body.velocity,
            .kinematic => |kin_body| kin_body.velocity,
            .static => Vector2.zero(),
        };
    }
};

pub const StaticBody = struct {
    shape: PhysicsShape,
    position: Vector2,
    rotation: f32 = 0.0,
    restitution: f32 = 0.5,
    friction: f32 = 0.7,

    pub fn init(shape: PhysicsShape, position: Vector2, opts: StaticBodyOptions) StaticBody {
        return StaticBody{
            .shape = shape,
            .position = position,
            .rotation = opts.rotation,
            .restitution = opts.restitution,
            .friction = opts.friction,
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
    velocity: Vector2 = Vector2{ .x = 0.0, .y = 0.0 },
    acceleration: Vector2 = Vector2{ .x = 0.0, .y = 0.0 },
    angular_velocity: f32 = 0.0,
    angular_acceleration: f32 = 0.0,
    mass: f32 = 1.0,
    inertia: f32 = 1.0,
    restitution: f32 = 0.5,
    friction: f32 = 0.5,

    // Sleep state
    is_sleeping: bool = false,
    sleep_time: f32 = 0.0,

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
        self.acceleration = Vector2{ .x = 0.0, .y = 0.0 };
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

fn drawShape(shape: PhysicsShape, position: Vector2, rotation_radians: f32, color: rl.Color) void {
    switch (shape) {
        .rectangle => |rect_shape| {
            const dest_rect = rl.Rectangle{
                .x = position.x,
                .y = position.y,
                .width = rect_shape.width,
                .height = rect_shape.height,
            };
            const origin = Vector2{ .x = rect_shape.width / 2.0, .y = rect_shape.height / 2.0 };
            // Convert radians to degrees for raylib's drawRectanglePro
            const rotation_degrees = std.math.radiansToDegrees(rotation_radians);
            rl.drawRectanglePro(dest_rect, origin, rotation_degrees, color);
        },
        .circle => |circle_shape| {
            rl.drawCircleV(position, circle_shape.radius, color);
        },
    }
}

pub const KinematicBody = struct {
    shape: PhysicsShape,
    position: Vector2,
    rotation: f32 = 0.0,
    velocity: Vector2 = Vector2{ .x = 0.0, .y = 0.0 },
    restitution: f32 = 0.0,
    friction: f32 = 0.0,

    const Self = @This();

    pub fn init(shape: PhysicsShape, position: Vector2, opts: KinematicBodyOptions) Self {
        return KinematicBody{
            .shape = shape,
            .position = position,
            .rotation = opts.rotation,
            .velocity = opts.velocity,
            .restitution = opts.restitution,
            .friction = opts.friction,
        };
    }

    pub fn aabb(self: Self) AABB {
        return computeAabb(self.shape, self.position, self.rotation);
    }

    pub fn draw(self: Self, color: rl.Color) void {
        return drawShape(self.shape, self.position, self.rotation, color);
    }

    pub fn update(self: *Self, deltaTime: f32) void {
        // Kinematic bodies move with constant velocity (set by user code)
        self.position = self.position.add(self.velocity.scale(deltaTime));
    }

    /// Set the velocity of this kinematic body
    pub fn setVelocity(self: *Self, velocity: Vector2) void {
        self.velocity = velocity;
    }

    /// Set the position of this kinematic body
    pub fn setPosition(self: *Self, position: Vector2) void {
        self.position = position;
    }
};
