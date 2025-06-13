const std = @import("std");

pub fn degreesToRadians(degrees: f32) f32 {
    return degrees * -(std.math.pi / 180.0);
}

pub fn radiansToDegrees(radians: f32) f32 {
    return radians * (180.0 / std.math.pi);
}
