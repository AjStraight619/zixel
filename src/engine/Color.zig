const Color = @This();

r: f32 = 1,
g: f32 = 1,
b: f32 = 1,
a: f32 = 1,

pub const white = Color{};
pub const black = Color{ .r = 0, .g = 0, .b = 0 };
pub const red = Color{ .r = 1, .g = 0, .b = 0 };
pub const green = Color{ .r = 0, .g = 1, .b = 0 };
pub const blue = Color{ .r = 0, .g = 0, .b = 1 };
pub const yellow = Color{ .r = 1, .g = 1, .b = 0 };
pub const cyan = Color{ .r = 0, .g = 1, .b = 1 };
pub const magenta = Color{ .r = 1, .g = 0, .b = 1 };
