const std = @import("std");
const math = std.math;

const Vec2 = @This();

x: f32,
y: f32,

pub const zero = Vec2{ .x = 0, .y = 0 };
pub const one = Vec2{ .x = 1, .y = 1 };

pub fn init(x: f32, y: f32) Vec2 {
    return .{ .x = x, .y = y };
}

pub fn add(self: Vec2, other: Vec2) Vec2 {
    return .{ .x = self.x + other.x, .y = self.y + other.y };
}

pub fn sub(self: Vec2, other: Vec2) Vec2 {
    return .{ .x = self.x - other.x, .y = self.y - other.y };
}

pub fn mul(self: Vec2, other: Vec2) Vec2 {
    return .{ .x = self.x * other.x, .y = self.y * other.y };
}

pub fn div(self: Vec2, other: Vec2) Vec2 {
    return .{ .x = self.x / other.x, .y = self.y / other.y };
}

pub fn dot(self: Vec2, other: Vec2) f32 {
    return self.x * other.x + self.y * other.y;
}

pub fn length(self: Vec2) f32 {
    return math.sqrt(self.x * self.x + self.y * self.y);
}

pub fn normalize(self: Vec2) Vec2 {
    const len = self.length();
    return .{ .x = self.x / len, .y = self.y / len };
}

pub fn rotate(self: Vec2, angle: f32) Vec2 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{
        .x = self.x * c - self.y * s,
        .y = self.x * s + self.y * c,
    };
}

pub fn scale(self: Vec2, scalar: f32) Vec2 {
    return .{ .x = self.x * scalar, .y = self.y * scalar };
}

pub fn lerp(self: Vec2, other: Vec2, t: f32) Vec2 {
    return .{
        .x = self.x + (other.x - self.x) * t,
        .y = self.y + (other.y - self.y) * t,
    };
}

pub fn clamp(self: Vec2, min: Vec2, max: Vec2) Vec2 {
    return .{
        .x = math.clamp(self.x, min.x, max.x),
        .y = math.clamp(self.y, min.y, max.y),
    };
}

/// Alias for sub (raylib compatibility)
pub fn subtract(self: Vec2, other: Vec2) Vec2 {
    return self.sub(other);
}

/// Alias for dot (raylib compatibility)
pub fn dotProduct(self: Vec2, other: Vec2) f32 {
    return self.dot(other);
}

/// Squared length (avoids sqrt for comparisons)
pub fn lengthSqr(self: Vec2) f32 {
    return self.x * self.x + self.y * self.y;
}

/// Distance to another vector
pub fn distance(self: Vec2, other: Vec2) f32 {
    return self.sub(other).length();
}

/// Squared distance (avoids sqrt for comparisons)
pub fn distanceSqr(self: Vec2, other: Vec2) f32 {
    return self.sub(other).lengthSqr();
}

/// Negate the vector
pub fn negate(self: Vec2) Vec2 {
    return .{ .x = -self.x, .y = -self.y };
}

/// Perpendicular vector (rotate 90 degrees)
pub fn perpendicular(self: Vec2) Vec2 {
    return .{ .x = -self.y, .y = self.x };
}
