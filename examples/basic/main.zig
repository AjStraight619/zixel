const std = @import("std");
const zig2d = @import("zig2d");
const Engine = zig2d.engine.Engine;
const Rectangle = zig2d.Rectangle;
const Body = zig2d.Body;
const Vector2 = zig2d.Vector2;
const DynamicBody = zig2d.DynamicBody;
const rl = @import("raylib");
pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    // Default engine config
    var game = try Engine.init(allocator, .{});

    _ = Body.initStatic(.{
        .rect = .{ .width = 100, .height = 100, .color = rl.Color.red },
    }, Vector2.zero(), .{});

    defer game.deinit();

    game.run();
}
