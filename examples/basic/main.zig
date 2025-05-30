const std = @import("std");
const zig2d = @import("zig2d");
const Engine = zig2d.engine.Engine;
const Rectangle = zig2d.Rectangle;
const Body = zig2d.Body;
const Vector2 = zig2d.Vector2;
const DynamicBody = zig2d.DynamicBody;
const rl = @import("raylib");

const EngineConfig = zig2d.engine.EngineConfig;
const GameAction = zig2d.GameAction;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    // Default engine config
    var game = try Engine.init(allocator, .{});

    const x = 100;
    const y = 100;

    const width = 100;
    const height = 100;

    const rect1 = Rectangle.init(x, y, width, height);

    _ = try game.physics.addBody(Body.initStatic(.{ .rectangle = rect1 }, Vector2.zero(), .{}));

    defer game.deinit();

    try game.run();
}
