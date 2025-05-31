const std = @import("std");
const rl = @import("raylib");
const WindowConfig = @import("config.zig").WindowConfig;

pub const Window = struct {
    config: WindowConfig,
    width: i32,
    height: i32,

    const Self = @This();

    pub fn init(config: WindowConfig) Self {
        rl.initWindow(
            @intCast(config.width),
            @intCast(config.height),
            config.title,
        );

        return Self{
            .config = config,
            .width = @intCast(config.width),
            .height = @intCast(config.height),
        };
    }

    pub fn deinit(self: Self) void {
        _ = self;
        rl.closeWindow();
    }

    pub fn getWindowSize(self: *const Self) struct { windowWidth: i32, windowHeight: i32 } {
        return .{ .windowWidth = self.width, .windowHeight = self.height };
    }
};
