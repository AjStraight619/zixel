const std = @import("std");
const zixel = @import("zixel");
const Engine = zixel.engine.Engine;
const Rectangle = zixel.Rectangle;
const Body = zixel.Body;
const Vector2 = zixel.Vector2;
const DynamicBody = zixel.DynamicBody;
const rl = @import("raylib");
const logging = zixel.logging;

const EngineConfig = zixel.engine.EngineConfig;
const GameAction = zixel.GameAction;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logging system and test build options
    logging.init();

    // Test different log levels and build options
    logging.general.info("Build options test - Debug enabled: {}, Profiling: {}, Physics debug: {}", .{ logging.isDebugEnabled(), logging.isProfilingEnabled(), logging.isPhysicsDebugEnabled() });

    logging.debugProfile("This is a profile debug message: {s}", .{"test"});
    logging.debugPhysics("This is a physics debug message: {s}", .{"test"});

    // Default engine config
    var game = try Engine.init(allocator, .{});

    const x = 100;
    const y = 100;

    const width = 100;
    const height = 100;

    const rect1 = Rectangle.init(x, y, width, height);

    _ = try game.physics.addBody(Body.initStatic(.{ .rectangle = rect1 }, Vector2.zero(), .{}));

    // Log the creation with our new system
    logging.physics.info("Creating static rectangle: {}x{} at ({d:.1}, {d:.1})", .{ width, height, @as(f32, @floatFromInt(x)), @as(f32, @floatFromInt(y)) });

    defer game.deinit();

    try game.run();
}
