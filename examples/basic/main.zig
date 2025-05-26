const std = @import("std");
const zig2d = @import("zig2d");
const Engine = zig2d.engine.Engine;
pub fn main() void {
    std.log.info("Hello, world!", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const game = try Engine.init(allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Zig2dEngine",
        },
        .physics = .{
            .gravity = 9.8,
        },
        .target_fps = 60,
    });

    defer game.deinit();

    game.run();
}
