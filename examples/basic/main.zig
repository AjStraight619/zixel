const std = @import("std");
const zig2d = @import("zig2d");
const Engine = zig2d.engine.Engine;
pub fn main() void {
    std.log.info("Hello, world!", .{});

    const game = try Engine.init(.{
        .width = 800,
        .height = 600,
        .title = "Zig2dEngine",
    });

    game.run();
}
