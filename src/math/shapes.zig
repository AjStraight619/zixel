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

/// Dimensions returned by PhysicsShape.size()
pub const Size = struct {
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

    // Short aliases
    pub const rect = initRectangle;
    pub const circ = initCircle;

    /// Get unified dimensions (works for both circles and rectangles)
    pub fn size(self: PhysicsShape) Size {
        return switch (self) {
            .rectangle => |r| .{ .width = r.width, .height = r.height },
            .circle => |c| .{ .width = c.radius * 2, .height = c.radius * 2 },
        };
    }

    /// Get the bounding radius (for broad phase)
    pub fn boundingRadius(self: PhysicsShape) f32 {
        return switch (self) {
            .circle => |c| c.radius,
            .rectangle => |r| @sqrt(r.width * r.width + r.height * r.height) / 2.0,
        };
    }

    pub const getBoundingRadius = boundingRadius;
};
