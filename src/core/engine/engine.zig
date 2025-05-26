const std = @import("std");
const rl = @import("raylib");
const Window = @import("../renderer/window.zig").Window;
const WindowConfig = @import("../renderer/config.zig").WindowConfig;
const PhysicsConfig = @import("../physics/config.zig").PhysicsConfig;
const PhysicsWorld = @import("../physics/world.zig").PhysicsWorld;

const EngineConfig = struct {
    window: WindowConfig,
    physics: PhysicsConfig,
    target_fps: u32,
};

pub const Engine = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    window: Window,
    physics: PhysicsWorld,
    target_fps: u32,

    pub fn init(alloc: std.mem.Allocator, config: EngineConfig) !Self {
        rl.setTargetFPS(config.target_fps);
        return Self{
            .allocator = alloc,
            .window = try Window.init(config.window),
            .physics = try PhysicsWorld.init(alloc, config.physics),
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

    pub fn setBackgroundColor(self: Self, color: rl.Color) void {
        _ = self;
        _ = color;
    }
};
