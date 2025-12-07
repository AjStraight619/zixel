const Vec2 = @import("../math/vec2.zig");

pub const Kind = enum {
    static,
    kinematic,
    dynamic,
};

pub const BodyHandle = struct {
    idx: u32,
    generation: u32,
};

pub const StaticBodyData = struct {
    pos: Vec2,
};

pub const KinematicBodyData = struct {
    pos: Vec2,
    vel: Vec2,
};

pub const DynamicBodyData = struct {
    pos: Vec2,
    vel: Vec2,
    force: Vec2,
    inv_mass: f32,
};

pub const Body = union(Kind) {
    static: StaticBodyData,
    kinematic: KinematicBodyData,
    dynamic: DynamicBodyData,
};

pub const BodySlot = struct {
    generation: u32,
    body: ?Body,
};
