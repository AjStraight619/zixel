const Vector2 = @import("vector2.zig").Vector2;

pub const AABB = struct {
    min: Vector2, // bottom-left or top-left
    max: Vector2, // top-right or bottom-right

    /// Create an AABB from min and max points
    pub fn fromMinMax(min: Vector2, max: Vector2) AABB {
        return AABB{ .min = min, .max = max };
    }

    /// Create an AABB from center and half-size
    pub fn fromCenterHalfSize(center_point: Vector2, half_size: Vector2) AABB {
        return AABB{
            .min = center_point.sub(half_size),
            .max = center_point.add(half_size),
        };
    }

    /// Check if a point is inside the AABB
    pub fn contains(self: AABB, point: Vector2) bool {
        return point.x >= self.min.x and point.x <= self.max.x and
            point.y >= self.min.y and point.y <= self.max.y;
    }

    /// Check if two AABBs intersect
    pub fn intersects(self: AABB, other: AABB) bool {
        return self.min.x <= other.max.x and self.max.x >= other.min.x and
            self.min.y <= other.max.y and self.max.y >= other.min.y;
    }

    /// Get the center of the AABB
    pub fn center(self: AABB) Vector2 {
        return Vector2.init(
            (self.min.x + self.max.x) / 2,
            (self.min.y + self.max.y) / 2,
        );
    }

    /// Get the size (width, height) of the AABB
    pub fn size(self: AABB) Vector2 {
        return Vector2.init(
            self.max.x - self.min.x,
            self.max.y - self.min.y,
        );
    }
};
