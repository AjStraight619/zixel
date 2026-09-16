const std = @import("std");
const World = @import("World.zig");
const Config = World.Config;
const CountingAllocator = @import("../core/allocators/CountingAllocator.zig");

test "benchmark broadphase churn" {
    const raw_alloc = std.testing.allocator;
    var counting = CountingAllocator.init(raw_alloc);
    const alloc = counting.allocator();

    // 1. Setup World with HIGH iterations
    var cfg = Config{};
    cfg.position_iterations = 8;
    var world = try World.init(alloc, cfg);
    defer world.deinit();

    const count = 2000;
    var rng = std.Random.DefaultPrng.init(0);
    const rand = rng.random();

    for (0..count) |_| {
        const x = rand.float(f32) * 500.0;
        const y = rand.float(f32) * 500.0;
        _ = try world.addDynamicCircle(x, y, 10.0, .{});
    }

    // 3. Measure 100 STEPS
    const started = std.Io.Clock.awake.now(std.testing.io);

    var total_steps: usize = 0;
    while (total_steps < 100) : (total_steps += 1) {
        // Prevent optimizer from skipping the loop
        std.mem.doNotOptimizeAway(total_steps);

        world.update(0.016);
    }

    // Force the compiler to acknowledge the world state changed
    std.mem.doNotOptimizeAway(world.accumulated_time);

    const duration = started.durationTo(std.Io.Clock.awake.now(std.testing.io)).toNanoseconds();

    std.debug.print("\n====================================\n", .{});
    std.debug.print("Bodies: {d}\n", .{count});
    std.debug.print("Iterations: 100 steps\n", .{});
    std.debug.print("Allocations: {d} bytes\n", .{counting.alloc_size});
    // Convert to MS per step
    const total_ms = @as(f64, @floatFromInt(duration)) / 1_000_000.0;
    std.debug.print("Total Time: {d:.2} ms\n", .{total_ms});
    std.debug.print("Time Per Step: {d:.2} ms\n", .{total_ms / 100.0});
    std.debug.print("====================================\n", .{});
}
