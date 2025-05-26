const std = @import("std");
const PhysicsConfig = @import("config.zig").PhysicsConfig;

pub const PhysicsWorld = struct {
    const Self = @This();
    alloc: std.mem.Allocator,
    config: PhysicsConfig,

    pub fn init(alloc: std.mem.Allocator, config: PhysicsConfig) !Self {
        return Self{
            .alloc = alloc,
            .config = config,
        };
    }
};
