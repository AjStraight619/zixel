const std = @import("std");
const zig2d = @import("zig2d");
const Engine = zig2d.engine.Engine;
const Rectangle = zig2d.Rectangle;
const Body = zig2d.Body;
const Vector2 = zig2d.Vector2;
const DynamicBody = zig2d.DynamicBody;
const rl = @import("raylib");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    // Default engine config
    var engine = try Engine.init(allocator, .{});
    try spawnCicleDynamicVsRectStatic(&engine);
    defer engine.deinit();
}

fn spawnCicleDynamicVsRectStatic(engine: *Engine) !void {
    const circle = Body.initDynamic(.{ .circle = .{ .radius = 10 } }, Vector2.init(100, 100), .{
        .velocity = Vector2.init(100, 0),
    });
    const rect = Body.initStatic(.{ .rectangle = .{ .x = 0, .y = 0, .width = 10, .height = 10 } }, Vector2.init(400, 100), .{});

    _ = try engine.physics.addBody(circle);
    _ = try engine.physics.addBody(rect);
}
