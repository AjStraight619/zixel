const Vec2 = @import("vec2.zig");

/// Axis-Aligned Bounding Box for broad-phase collision detection
pub const AABB = @This();

min: Vec2,
max: Vec2,

/// Create an AABB from min and max points
pub fn fromMinMax(min: Vec2, max: Vec2) AABB {
    return .{ .min = min, .max = max };
}

/// Create an AABB from center and half-extents
pub fn fromCenterHalfExtents(c: Vec2, half_extents: Vec2) AABB {
    return .{
        .min = c.sub(half_extents),
        .max = c.add(half_extents),
    };
}

/// Create an AABB from center and full size
pub fn fromCenterSize(c: Vec2, s: Vec2) AABB {
    const half = s.scale(0.5);
    return fromCenterHalfExtents(c, half);
}

/// Check if this AABB intersects another
pub fn intersects(self: AABB, other: AABB) bool {
    return self.max.x >= other.min.x and
        self.min.x <= other.max.x and
        self.max.y >= other.min.y and
        self.min.y <= other.max.y;
}

/// Check if this AABB contains a point
pub fn containsPoint(self: AABB, point: Vec2) bool {
    return point.x >= self.min.x and
        point.x <= self.max.x and
        point.y >= self.min.y and
        point.y <= self.max.y;
}

/// Get the center of the AABB
pub fn center(self: AABB) Vec2 {
    return .{
        .x = (self.min.x + self.max.x) / 2.0,
        .y = (self.min.y + self.max.y) / 2.0,
    };
}

/// Get the size of the AABB
pub fn size(self: AABB) Vec2 {
    return .{
        .x = self.max.x - self.min.x,
        .y = self.max.y - self.min.y,
    };
}

/// Get the half-extents of the AABB
pub fn halfExtents(self: AABB) Vec2 {
    return self.size().scale(0.5);
}

/// Expand the AABB to include a point
pub fn expandToInclude(self: *AABB, point: Vec2) void {
    self.min.x = @min(self.min.x, point.x);
    self.min.y = @min(self.min.y, point.y);
    self.max.x = @max(self.max.x, point.x);
    self.max.y = @max(self.max.y, point.y);
}

/// Merge two AABBs
pub fn merge(self: AABB, other: AABB) AABB {
    return .{
        .min = .{
            .x = @min(self.min.x, other.min.x),
            .y = @min(self.min.y, other.min.y),
        },
        .max = .{
            .x = @max(self.max.x, other.max.x),
            .y = @max(self.max.y, other.max.y),
        },
    };
}
