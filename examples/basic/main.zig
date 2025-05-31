const std = @import("std");
const zixel = @import("zixel");
const Engine = zixel.engine.Engine;
const Rectangle = zixel.Rectangle;
const Body = zixel.Body;
const Vector2 = zixel.Vector2;
const DynamicBody = zixel.DynamicBody;
const rl = @import("raylib");

const EngineConfig = zixel.engine.EngineConfig;
const GameAction = zixel.GameAction;

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
