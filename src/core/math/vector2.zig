const math = @import("std").math;
const assert = @import("std").debug.assert;

pub const Vector2 = struct {
    x: f32,
    y: f32,

    const Vector2Error = error{
        DivisionByZero,
        CannotNormalizeZeroVector,
        CannotProjectOntoZeroVector,
    };

    const Self = @This();

    pub fn zero() Self {
        return Self{ .x = 0, .y = 0 };
    }

    pub fn add(self: Self, other: Vector2) Self {
        return Self{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: Self, other: Vector2) Self {
        return Self{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn mul(self: Self, other: Vector2) Self {
        return Self{ .x = self.x * other.x, .y = self.y * other.y };
    }

    pub fn div(self: Self, other: Vector2) Self {
        // Ensure no division by zero
        if (other.x == 0 or other.y == 0) {
            @panic("Division by zero");
        }
        return Self{ .x = self.x / other.x, .y = self.y / other.y };
    }

    pub fn scale(self: Self, scalar: f32) Vector2 {
        return Vector2{
            .x = self.x * scalar,
            .y = self.y * scalar,
        };
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

    pub fn dot(self: Self, other: Vector2) f32 {
        return self.x * other.x + self.y * other.y;
    }

    pub fn cross(self: Self, other: Vector2) f32 {
        return self.x * other.y - self.y * other.x;
    }

    pub fn rotate(self: Self, angle: f32) Self {
        return Self{ .x = self.x * @cos(angle) - self.y * @sin(angle), .y = self.x * @sin(angle) + self.y * @cos(angle) };
    }

    pub fn lerp(self: Self, other: Vector2, t: f32) Self {
        return Self{ .x = math.lerp(self.x, other.x, t), .y = math.lerp(self.y, other.y, t) };
    }

    pub fn distance(self: Self, other: Vector2) f32 {
        return math.sqrt((self.x - other.x) * (self.x - other.x) + (self.y - other.y) * (self.y - other.y));
    }

    pub fn reflect(self: Self, normal: Vector2) Self {
        return self.sub(normal.mul(self.dot(normal)));
    }

    pub fn project(self: Self, other: Vector2) Self {
        if (other.len() == 0) {
            @panic("Cannot project onto zero vector");
        }
        return other.mul(self.dot(other) / other.dot(other));
    }
};

test "Vector2" {
    const v1 = Vector2.init(1, 2);
    const v2 = Vector2.init(3, 4);
    _ = v1.add(v2);
    const v3 = Vector2.init(1, 1);
    const v4 = Vector2.init(0, 1);
    _ = v3.div(v4);
}

test "force fail" {
    @panic("This should fail!");
}
