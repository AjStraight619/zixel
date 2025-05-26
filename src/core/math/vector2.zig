const math = @import("std").math;
const assert = @import("std").debug.assert;

pub const Vector2 = struct {
    x: f32,
    y: f32,

    const Self = @This();

    pub fn init(x: f32, y: f32) Self {
        return Self{ .x = x, .y = y };
    }

    pub fn add(self: Self, other: Self) Self {
        return Self{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: Self, other: Self) Self {
        return Self{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn mul(self: Self, other: Self) Self {
        return Self{ .x = self.x * other.x, .y = self.y * other.y };
    }

    pub fn div(self: Self, other: Self) Self {
        // Ensure no division by zero
        if (other.x == 0 or other.y == 0) {
            @panic("Division by zero");
        }
        return Self{ .x = self.x / other.x, .y = self.y / other.y };
    }

    pub fn len(self: Self) f32 {
        return math.sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn normalize(self: Self) Self {
        const length = self.len();
        if (length == 0) {
            @panic("Cannot normalize zero vector");
        }
        return Self{ .x = self.x / length, .y = self.y / length };
    }
};
