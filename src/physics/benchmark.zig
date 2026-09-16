//! Repeatable headless measurements. Setup, warm-up, validation and printing
//! are excluded from timings; broadphase allocation during updates is included.
const std = @import("std");
const builtin = @import("builtin");
const World = @import("../engine/World.zig");
const Physics = @import("Physics.zig");
const Vec2 = @import("../math/Vec2.zig");
const CountingAllocator = @import("../core/allocators/CountingAllocator.zig");

pub const Scenario = enum {
    sparse,
    circles,
    mixed_awake,
    mixed_sleeping,
    broadphase_positive,
    broadphase_negative,
};

const repeats = 5;
const warmup_steps = 60;
const measured_steps = 180;

pub fn run(comptime scenario: Scenario) !void {
    const broadphase_only = scenario == .broadphase_positive or scenario == .broadphase_negative;
    const count: usize = if (broadphase_only) 128 else 2000;
    var samples: [repeats * measured_steps]f64 = undefined;
    var run_means: [repeats]f64 = undefined;
    var active: u64 = 0;
    var sleeping: u64 = 0;
    var pairs: u64 = 0;
    var contacts: u64 = 0;
    var allocated: u64 = 0;
    var actual_steps: u64 = 0;
    var outside: usize = 0;
    var state_hash: ?u64 = null;

    for (0..repeats) |repeat| {
        // Match the allocator used by the graphical physics sample. Avoid the
        // test allocator's tracking overhead in measurements, including Debug.
        var counting = CountingAllocator.init(std.heap.page_allocator);
        var world = World.init(counting.allocator());
        defer world.deinit();
        var physics = try Physics.init(counting.allocator(), .{
            .allow_sleeping = scenario == .mixed_sleeping,
            .position_iterations = if (scenario == .circles) 8 else 4,
            .gravity = .{ .x = 0, .y = if (scenario == .mixed_awake or scenario == .mixed_sleeping) 980 else 0 },
        });
        defer physics.deinit();
        try populate(&world, scenario, count);

        for (0..warmup_steps) |_| try advance(&world, &physics, broadphase_only);
        const allocation_start = counting.alloc_size;
        const step_start = physics.step_count;
        var total_ns: f64 = 0;
        for (0..measured_steps) |i| {
            const before = std.Io.Clock.awake.now(std.testing.io);
            try advance(&world, &physics, broadphase_only);
            const elapsed = before.durationTo(std.Io.Clock.awake.now(std.testing.io)).toNanoseconds();
            try std.testing.expect(elapsed >= 0);
            const ns: f64 = @floatFromInt(elapsed);
            samples[repeat * measured_steps + i] = ns;
            total_ns += ns;
            active += physics.debug_stats.active_bodies;
            sleeping += physics.debug_stats.sleeping_bodies;
            pairs += physics.spatial_hash.pairs.items.len;
            contacts += physics.debug_stats.collisions_found;
        }
        allocated += counting.alloc_size - allocation_start;
        const steps = physics.step_count - step_start;
        try std.testing.expectEqual(@as(u64, if (broadphase_only) 0 else measured_steps), steps);
        actual_steps += steps;
        run_means[repeat] = total_ns / measured_steps;

        // Validate observable state outside the timed region. This is a sanity
        // check, not a claim that finite bodies have correct collision response.
        var state = std.hash.Wyhash.init(0);
        var bodies = world.bodies();
        while (bodies.next()) |body| {
            try std.testing.expect(std.math.isFinite(body.position.x));
            try std.testing.expect(std.math.isFinite(body.position.y));
            try std.testing.expect(std.math.isFinite(body.velocity.x));
            try std.testing.expect(std.math.isFinite(body.velocity.y));
            try std.testing.expect(std.math.isFinite(body.rotation));
            try std.testing.expect(std.math.isFinite(body.angular_velocity));
            const values = [_]f32{ body.position.x, body.position.y, body.velocity.x, body.velocity.y, body.rotation, body.angular_velocity };
            state.update(std.mem.asBytes(&values));
            state.update(&.{@intFromBool(body.isSleeping())});
            if ((scenario == .mixed_awake or scenario == .mixed_sleeping) and body.kind == .dynamic) {
                if (body.position.x < 200 or body.position.x > 1200 or body.position.y < 200 or body.position.y > 1200) outside += 1;
            }
        }
        const hash = state.final();
        if (state_hash) |expected| try std.testing.expectEqual(expected, hash);
        state_hash = hash;
        std.mem.doNotOptimizeAway(world.slots.items);
    }

    var mean: f64 = 0;
    for (run_means) |value| mean += value / repeats;
    std.mem.sort(f64, &samples, {}, std.sort.asc(f64));
    std.mem.sort(f64, &run_means, {}, std.sort.asc(f64));
    const n: f64 = samples.len;
    std.debug.print("\nBENCH {s} mode={s} bodies={d} repeats={d} warmup={d} samples={d} physics_steps={d}\n", .{
        @tagName(scenario), @tagName(builtin.mode), count, repeats, warmup_steps, samples.len, actual_steps,
    });
    std.debug.print("  ms/update mean={d:.4} p50={d:.4} p95={d:.4} p99={d:.4} max={d:.4} run_mean_min={d:.4} run_mean_max={d:.4}\n", .{
        mean / 1e6,
        percentile(&samples, 50) / 1e6,
        percentile(&samples, 95) / 1e6,
        percentile(&samples, 99) / 1e6,
        samples[samples.len - 1] / 1e6,
        run_means[0] / 1e6,
        run_means[repeats - 1] / 1e6,
    });
    std.debug.print("  avg awake={d:.1} sleeping={d:.1} pairs={d:.1} contacts={d:.1} allocation_growth_bytes/run={d} escaped_centers/run={d:.1} state_hash={x}\n", .{
        @as(f64, @floatFromInt(active)) / n,
        @as(f64, @floatFromInt(sleeping)) / n,
        @as(f64, @floatFromInt(pairs)) / n,
        @as(f64, @floatFromInt(contacts)) / n,
        allocated / repeats,
        @as(f64, @floatFromInt(outside)) / repeats,
        state_hash.?,
    });
}

fn percentile(sorted: []const f64, percent: usize) f64 {
    // Nearest-rank percentile, including the maximum at p100.
    return sorted[(sorted.len * percent + 99) / 100 - 1];
}

fn advance(world: *World, physics: *Physics, comptime broadphase_only: bool) !void {
    if (broadphase_only) {
        try physics.spatial_hash.update(world.bodies());
    } else {
        // Exactly one fixed timestep; no 0.016-vs-1/60 undercount.
        physics.update(world.bodies(), physics.cfg.physics_time_step);
    }
}

fn populate(world: *World, comptime scenario: Scenario, count: usize) !void {
    var rng = std.Random.DefaultPrng.init(42);
    const random = rng.random();
    if (scenario == .mixed_awake or scenario == .mixed_sleeping) {
        // Start the arena in positive coordinates. Escaping bodies can later
        // reach negative coordinates; the translated cases isolate that bug.
        _ = try world.addStaticRect(700, 1250, 1200, 100, .{});
        _ = try world.addStaticRect(700, 150, 1200, 100, .{});
        _ = try world.addStaticRect(150, 700, 100, 1000, .{});
        _ = try world.addStaticRect(1250, 700, 100, 1000, .{});
    }
    for (0..count) |i| {
        switch (scenario) {
            .sparse => {
                _ = try world.addDynamicCircle(200 + @as(f32, @floatFromInt(i % 50)) * 80, 200 + @as(f32, @floatFromInt(i / 50)) * 80, 8, .{ .velocity = .{ .x = 30, .y = 0 } });
            },
            .circles => {
                _ = try world.addDynamicCircle(200 + random.float(f32) * 500, 200 + random.float(f32) * 500, 10, .{});
            },
            .mixed_awake, .mixed_sleeping => {
                const x = 220 + random.float(f32) * 960;
                const y = 220 + random.float(f32) * 960;
                const velocity = Vec2{ .x = random.float(f32) * 400 - 200, .y = random.float(f32) * 400 - 200 };
                if (i % 2 == 0) {
                    _ = try world.addDynamicCircle(x, y, 8, .{ .velocity = velocity });
                } else {
                    _ = try world.addDynamicRect(x, y, 15, 15, .{ .velocity = velocity, .rotation = random.float(f32) * std.math.pi * 2 });
                }
            },
            .broadphase_positive, .broadphase_negative => {
                // The same non-overlapping rectangles translated by whole hash
                // cells. Correct AABBs yield zero candidate pairs in both cases.
                const offset: f32 = if (scenario == .broadphase_positive) 128 else -640;
                _ = try world.addDynamicRect(offset + @as(f32, @floatFromInt(i % 16)) * 32, offset + @as(f32, @floatFromInt(i / 16)) * 32, 15, 15, .{ .rotation = 0.3 });
            },
        }
    }
}
