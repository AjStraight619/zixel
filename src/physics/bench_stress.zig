const std = @import("std");
const World = @import("World.zig");
const Config = World.Config;
const Vec2 = @import("../math/Vec2.zig");
const CountingAllocator = @import("../core/allocators/CountingAllocator.zig");

test "benchmark: pressure cooker (mixed shapes)" {
    const raw_alloc = std.testing.allocator;
    var counting = CountingAllocator.init(raw_alloc);
    const alloc = counting.allocator();

    // 1. Setup World
    var cfg = Config{};
    cfg.position_iterations = 4;
    var world = try World.init(alloc, cfg);
    defer world.deinit();

    var rng = std.Random.DefaultPrng.init(42);
    const rand = rng.random();

    // 2. The Arena (Constraint Box)
    const wall_thickness = 100.0;
    const arena_size = 1000.0;

    // Floor
    // Corrected: Removed the '0' argument.
    _ = try world.addStaticRect(arena_size / 2.0, arena_size + wall_thickness / 2.0, arena_size + 200, wall_thickness, .{});
    // Ceiling
    _ = try world.addStaticRect(arena_size / 2.0, -wall_thickness / 2.0, arena_size + 200, wall_thickness, .{});
    // Left Wall
    _ = try world.addStaticRect(-wall_thickness / 2.0, arena_size / 2.0, wall_thickness, arena_size, .{});
    // Right Wall
    _ = try world.addStaticRect(arena_size + wall_thickness / 2.0, arena_size / 2.0, wall_thickness, arena_size, .{});

    // 3. Spawn 2000 Bodies
    const body_count = 2000;

    for (0..body_count) |i| {
        const x = rand.float(f32) * (arena_size - 40.0) + 20.0;
        const y = rand.float(f32) * (arena_size - 40.0) + 20.0;

        const vx = (rand.float(f32) * 400.0) - 200.0;
        const vy = (rand.float(f32) * 400.0) - 200.0;
        const velocity = Vec2.init(vx, vy);

        if (i % 2 == 0) {
            _ = try world.addDynamicCircle(x, y, 8.0, .{ .velocity = velocity });
        } else {
            const rot = rand.float(f32) * std.math.pi * 2.0;
            // Corrected: Moved 'rot' into BodyOptions, changed Box -> Rect
            _ = try world.addDynamicRect(x, y, 15.0, 15.0, .{ .velocity = velocity, .rotation = rot });
        }
    }

    // 4. Run Benchmark
    const steps = 120;
    const dt = 0.01667;

    const started = std.Io.Clock.awake.now(std.testing.io);

    var step: usize = 0;
    while (step < steps) : (step += 1) {
        std.mem.doNotOptimizeAway(step);
        world.update(dt);
    }

    std.mem.doNotOptimizeAway(world.accumulated_time);

    const duration = started.durationTo(std.Io.Clock.awake.now(std.testing.io)).toNanoseconds();

    // 5. Report
    std.debug.print("\n====================================\n", .{});
    std.debug.print("PRESSURE COOKER BENCHMARK\n", .{});
    std.debug.print("------------------------------------\n", .{});
    std.debug.print("Bodies: {d} (Mixed Circle/Rect)\n", .{body_count});
    std.debug.print("Arena:  {d}x{d}\n", .{ arena_size, arena_size });
    std.debug.print("Steps:  {d}\n", .{steps});
    std.debug.print("Allocations: {d} bytes\n", .{counting.alloc_size});

    const total_ms = @as(f64, @floatFromInt(duration)) / 1_000_000.0;
    std.debug.print("Total Time:    {d:.2} ms\n", .{total_ms});
    std.debug.print("Time Per Step: {d:.2} ms\n", .{total_ms / @as(f64, @floatFromInt(steps))});
    std.debug.print("FPS Potential: {d:.0}\n", .{1000.0 / (total_ms / @as(f64, @floatFromInt(steps)))});
    std.debug.print("====================================\n", .{});
}
