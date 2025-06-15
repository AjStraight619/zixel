const std = @import("std");
const rl = @import("raylib");

pub const WindowConfig = struct {
    width: u32 = 800,
    height: u32 = 600,
    title: [:0]const u8 = "Zig2D", // Need to match the C string type
};

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

    pub fn getSize(self: *const Self) struct { windowWidth: i32, windowHeight: i32 } {
        return .{ .windowWidth = self.width, .windowHeight = self.height };
    }
};
