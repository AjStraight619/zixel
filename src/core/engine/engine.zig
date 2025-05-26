const std = @import("std");
const rl = @import("raylib");
const Window = @import("../renderer/window.zig").Window;
const WindowConfig = @import("../renderer/window.zig").WindowConfig;

pub const Engine = struct {
    const Self = @This();
    window: Window,

    pub fn init(config: WindowConfig) !Self {
        return Self{
            .window = try Window.init(config),
        };
    }

    pub fn deinit(self: Self) void {
        self.window.deinit();
    }

    pub fn run(self: Self) void {
        _ = self;
        while (!rl.windowShouldClose()) {
            rl.beginDrawing();
            rl.endDrawing();
        }
    }
};
