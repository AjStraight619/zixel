const rl = @import("raylib");
const Vector2 = @import("vector2.zig");
const AABB = @import("aabb.zig");

pub const Shape = union(enum) {
    rect: Rectangle,
    circle: Circle,

    const Self = @This();

    pub fn aabb(self: Self) AABB {
        switch (self) {
            .rect => |rect| {
                const half = Vector2.init(rect.width / 2, rect.height / 2);
                return AABB.fromMinMax(half.negate(), half);
            },
            .circle => |circle| {
                const r = circle.radius;
                return AABB.fromMinMax(Vector2.init(-r, -r), Vector2.init(r, r));
            },
        }
    }
};

pub const Rectangle = struct {
    width: f32,
    height: f32,
    color: rl.Color,
};

pub const Circle = struct {
    radius: f32,
    color: rl.Color,
};
