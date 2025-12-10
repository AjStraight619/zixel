const Vec2 = @import("vec2.zig");

/// Circle shape for physics collision
pub const Circle = struct {
    radius: f32,
};

/// Rectangle shape for physics collision
/// Width and height are the full dimensions (not half-extents)
pub const Rectangle = struct {
    width: f32,
    height: f32,
};

/// Physics shape used for collision detection
pub const PhysicsShape = union(enum) {
    circle: Circle,
    rectangle: Rectangle,

    /// Create a circle shape
    pub fn initCircle(radius: f32) PhysicsShape {
        return .{ .circle = .{ .radius = radius } };
    }

    /// Create a rectangle shape
    pub fn initRectangle(width: f32, height: f32) PhysicsShape {
        return .{ .rectangle = .{ .width = width, .height = height } };
    }

    /// Get the bounding radius (for broad phase)
    pub fn getBoundingRadius(self: PhysicsShape) f32 {
        return switch (self) {
            .circle => |c| c.radius,
            .rectangle => |r| @sqrt(r.width * r.width + r.height * r.height) / 2.0,
        };
    }
};
