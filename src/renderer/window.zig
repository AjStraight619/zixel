const std = @import("std");
const rl = @import("raylib");
const WindowConfig = @import("config.zig").WindowConfig;

pub const Window = struct {
    config: WindowConfig,

    const Self = @This();

    pub fn init(config: WindowConfig) Self {
        rl.initWindow(
            @intCast(config.width),
            @intCast(config.height),
            config.title,
        );

        return Self{
            .config = config,
        };
    }

    pub fn deinit(self: Self) void {
        _ = self;
        rl.closeWindow();
    }
};
