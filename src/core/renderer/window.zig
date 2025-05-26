const std = @import("std");
const rl = @import("raylib");

pub const WindowConfig = struct {
    width: u32,
    height: u32,
    title: []const u8,
};

pub const Window = struct {
    config: WindowConfig,

    const Self = @This();

    pub fn init(config: WindowConfig) !Self {
        return Self{
            .config = config,
        };
    }

    pub fn deinit() void {
        rl.closeWindow();
    }
};
