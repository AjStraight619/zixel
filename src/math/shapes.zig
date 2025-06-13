const rl = @import("raylib");

pub const PhysicsShape = union(enum) {
    rectangle: rl.Rectangle,
    circle: struct { radius: f32 },
};
