const std = @import("std");
const World = @import("World.zig");
const Physics = @import("../physics/Physics.zig");

test "moving kinematic collider pushes awake and sleeping dynamic bodies" {
    for ([_]bool{ false, true }) |sleeping| {
        var world = World.init(std.testing.allocator);
        defer world.deinit();
        var physics = try Physics.init(std.testing.allocator, .{
            .gravity = .{ .x = 0, .y = 0 },
            .linear_damping = 0,
            .contact_slop = 0,
            .baumgarte_factor = 1,
            .sleep_velocity_threshold = 0.01,
        });
        defer physics.deinit();
        const dynamic_handle = try world.addDynamicCircle(0, 0, 1, .{ .restitution = 0, .friction = 0 });
        const kinematic_handle = try world.addKinematicCircle(1.9, 0, 1, .{
            .velocity = .{ .x = -10, .y = 0 },
            .restitution = 0,
            .friction = 0,
        });
        const dynamic = world.getBody(dynamic_handle).?;
        const kinematic = world.getBody(kinematic_handle).?;
        if (sleeping) dynamic.putToSleep();
        physics.update(world.bodies(), physics.cfg.physics_time_step);
        try std.testing.expect(!dynamic.isSleeping());
        try std.testing.expectApproxEqAbs(@as(f32, -10), dynamic.velocity.x, 0.0001);
        try std.testing.expectEqual(@as(f32, -10), kinematic.velocity.x);
        try std.testing.expectApproxEqAbs(1.9 - 10 * physics.cfg.physics_time_step, kinematic.position.x, 0.0001);
        const previous_x = dynamic.position.x;
        physics.update(world.bodies(), physics.cfg.physics_time_step);
        try std.testing.expectApproxEqAbs(previous_x - 10 * physics.cfg.physics_time_step, dynamic.position.x, 0.0001);
    }
}

test "kinematic motion integrates angular velocity while static bodies stay fixed" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    var physics = try Physics.init(std.testing.allocator, .{});
    defer physics.deinit();
    const handle = try world.addKinematicRect(0, 0, 2, 2, .{});
    const stationary = try world.addStaticRect(100, 0, 2, 2, .{});
    world.getBody(handle).?.angular_velocity = 2;
    world.getBody(stationary).?.angular_velocity = 2;
    physics.update(world.bodies(), physics.cfg.physics_time_step);
    try std.testing.expectApproxEqAbs(2 * physics.cfg.physics_time_step, world.getBody(handle).?.rotation, 0.0001);
    try std.testing.expectEqual(@as(f32, 2), world.getBody(handle).?.angular_velocity);
    try std.testing.expectEqual(@as(f32, 0), world.getBody(stationary).?.rotation);
}

test "force on a sleeping body is integrated once even with immediate sleeping enabled" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    var physics = try Physics.init(std.testing.allocator, .{
        .gravity = .{ .x = 0, .y = 0 },
        .sleep_time_threshold = 0,
        .linear_damping = 0,
    });
    defer physics.deinit();
    const handle = try world.addDynamicCircle(0, 0, 1, .{ .mass = 2 });
    const body = world.getBody(handle).?;
    body.putToSleep();
    body.applyForce(.{ .x = 120, .y = 0 });
    physics.update(world.bodies(), physics.cfg.physics_time_step);
    try std.testing.expect(!body.isSleeping());
    try std.testing.expectApproxEqAbs(@as(f32, 1), body.velocity.x, 0.00001);
    try std.testing.expectApproxEqAbs(physics.cfg.physics_time_step, body.position.x, 0.00001);
    // Prevent sleeping on the second step so stale force accumulation is visible.
    physics.cfg.allow_sleeping = false;
    physics.update(world.bodies(), physics.cfg.physics_time_step);
    try std.testing.expectApproxEqAbs(@as(f32, 1), body.velocity.x, 0.00001);
}

test "gravity allows supported bodies to sleep and does not wake them" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    var physics = try Physics.init(std.testing.allocator, .{
        .gravity = .{ .x = 0, .y = 10 },
        .sleep_time_threshold = 0.05,
        .contact_slop = 0,
        .baumgarte_factor = 1,
    });
    defer physics.deinit();
    const handle = try world.addDynamicCircle(0, 0, 1, .{ .restitution = 0 });
    _ = try world.addStaticRect(0, 2, 100, 2, .{ .restitution = 0 });
    for (0..30) |_| physics.update(world.bodies(), physics.cfg.physics_time_step);
    const body = world.getBody(handle).?;
    try std.testing.expect(body.isSleeping());
    try std.testing.expectApproxEqAbs(@as(f32, 0), body.position.y, 0.001);
    const position = body.position;
    physics.update(world.bodies(), physics.cfg.physics_time_step);
    try std.testing.expect(body.isSleeping());
    try std.testing.expectEqual(position, body.position);
}

test "separated rectangles generate no broadphase pairs on either side of the origin" {
    for ([_]f32{ 128, -640 }) |offset| {
        var world = World.init(std.testing.allocator);
        defer world.deinit();
        var physics = try Physics.init(std.testing.allocator, .{});
        defer physics.deinit();
        for (0..128) |i| {
            _ = try world.addDynamicRect(
                offset + @as(f32, @floatFromInt(i % 16)) * 32,
                offset + @as(f32, @floatFromInt(i / 16)) * 32,
                15,
                15,
                .{ .rotation = 0.3 },
            );
        }
        try physics.spatial_hash.update(world.bodies());
        try std.testing.expectEqual(@as(usize, 0), physics.spatial_hash.pairs.items.len);
    }
}

test "body iterator preserves broadphase pairs and skips removed entities" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    var physics = try Physics.init(std.testing.allocator, .{});
    defer physics.deinit();
    // Large bodies overlap multiple hash cells but produce just one pair.
    const first = try world.addDynamicRect(0, 0, 140, 140, .{});
    const second = try world.addStaticRect(0, 0, 140, 140, .{});
    try physics.spatial_hash.update(world.bodies());
    try std.testing.expectEqual(@as(usize, 1), physics.spatial_hash.pairs.items.len);
    const pair = physics.spatial_hash.pairs.items[0];
    const a = world.getBody(first).?;
    const b = world.getBody(second).?;
    try std.testing.expect((pair.a == a and pair.b == b) or (pair.a == b and pair.b == a));
    world.clearAll(false);
    _ = try world.addDynamicRect(0, 0, 10, 10, .{});
    try physics.spatial_hash.update(world.bodies());
    try std.testing.expectEqual(@as(usize, 0), physics.spatial_hash.pairs.items.len);
}

test "physics advances world bodies only when a full time step accumulates" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    var physics = try Physics.init(std.testing.allocator, .{
        .gravity = .{ .x = 0, .y = 10 },
        .physics_time_step = 0.1,
        .max_delta_time = 0.1,
        .allow_sleeping = false,
        .linear_damping = 0,
        .angular_damping = 0,
    });
    defer physics.deinit();
    const dynamic = try world.addDynamicRect(0, 0, 1, 1, .{});
    const stationary = try world.addStaticRect(100, 0, 1, 1, .{});
    const kinematic = try world.addKinematicRect(200, 0, 1, 1, .{ .velocity = .{ .x = 10, .y = 0 } });
    physics.update(world.bodies(), 0.05);
    try std.testing.expectEqual(@as(u64, 0), physics.step_count);
    try std.testing.expectEqual(@as(f32, 0), world.getBody(dynamic).?.position.y);
    physics.update(world.bodies(), 0.05);
    try std.testing.expectEqual(@as(u64, 1), physics.step_count);
    try std.testing.expectApproxEqAbs(@as(f32, 1), world.getBody(dynamic).?.velocity.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), world.getBody(dynamic).?.position.y, 0.0001);
    try std.testing.expectEqual(@as(f32, 0), world.getBody(stationary).?.position.y);
    try std.testing.expectApproxEqAbs(@as(f32, 201), world.getBody(kinematic).?.position.x, 0.0001);
    // A fresh iterator still works after growing entity storage.
    for (0..100) |i| _ = try world.addStaticRect(@as(f32, @floatFromInt(i)) * 10, 1000, 1, 1, .{});
    physics.update(world.bodies(), 0.1);
    try std.testing.expectEqual(@as(u64, 2), physics.step_count);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), world.getBody(dynamic).?.position.y, 0.0001);
}

fn stepFor(physics: *Physics, world: *World, seconds: f32) void {
    const steps: usize = @intFromFloat(seconds / physics.cfg.physics_time_step);
    for (0..steps) |_| physics.update(world.bodies(), physics.cfg.physics_time_step);
}

test "a box dropped far from a wide floor's centre settles flat in either spawn order" {
    for ([_]bool{ false, true }) |floor_first| {
        var world = World.init(std.testing.allocator);
        defer world.deinit();
        var physics = try Physics.init(std.testing.allocator, .{});
        defer physics.deinit();
        var box_handle: World.EntityHandle = undefined;
        if (floor_first) {
            _ = try world.addStaticRect(0, 120, 1200, 20, .{ .restitution = 0 });
            box_handle = try world.addDynamicRect(500, 0, 20, 20, .{ .restitution = 0 });
        } else {
            box_handle = try world.addDynamicRect(500, 0, 20, 20, .{ .restitution = 0 });
            _ = try world.addStaticRect(0, 120, 1200, 20, .{ .restitution = 0 });
        }
        stepFor(&physics, &world, 4);
        const box = world.getBody(box_handle).?;
        // Floor top is y = 110, so a resting 20 px box is centred near y = 100.
        try std.testing.expectApproxEqAbs(@as(f32, 100), box.position.y, 1.5);
        try std.testing.expectApproxEqAbs(@as(f32, 500), box.position.x, 0.5);
        try std.testing.expectApproxEqAbs(@as(f32, 0), box.rotation, 0.001);
        try std.testing.expect(box.isSleeping());
    }
}

test "heavy bodies are held up by the floor instead of sinking through it" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    var physics = try Physics.init(std.testing.allocator, .{ .allow_sleeping = false });
    defer physics.deinit();
    const handle = try world.addDynamicCircle(0, 0, 10, .{ .mass = 100, .restitution = 0 });
    _ = try world.addStaticRect(0, 20, 400, 20, .{ .restitution = 0 });
    stepFor(&physics, &world, 3);
    const body = world.getBody(handle).?;
    try std.testing.expect(@abs(body.velocity.y) < 20);
    try std.testing.expectApproxEqAbs(@as(f32, 0), body.position.y, 1.5);
}

test "a body spinning in place is not put to sleep" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    var physics = try Physics.init(std.testing.allocator, .{
        .gravity = .{ .x = 0, .y = 0 },
        .angular_damping = 0,
    });
    defer physics.deinit();
    const handle = try world.addDynamicRect(0, 0, 10, 10, .{});
    const body = world.getBody(handle).?;
    body.angular_velocity = 15;
    stepFor(&physics, &world, 1);
    try std.testing.expect(!body.isSleeping());
    try std.testing.expectEqual(@as(f32, 15), body.angular_velocity);
    // A body that is barely turning still settles.
    body.angular_velocity = 0.1;
    stepFor(&physics, &world, 1);
    try std.testing.expect(body.isSleeping());
}

test "a body asleep on a kinematic platform wakes when the platform starts moving" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    var physics = try Physics.init(std.testing.allocator, .{});
    defer physics.deinit();
    const box_handle = try world.addDynamicRect(0, -20, 20, 20, .{ .restitution = 0 });
    const platform_handle = try world.addKinematicRect(0, 0, 100, 20, .{ .restitution = 0 });
    stepFor(&physics, &world, 2);
    const box = world.getBody(box_handle).?;
    try std.testing.expect(box.isSleeping());
    const rest_y = box.position.y;

    world.getBody(platform_handle).?.velocity = .{ .x = 200, .y = 0 };
    stepFor(&physics, &world, 2);
    // The platform has left; the box woke up and fell instead of floating.
    try std.testing.expect(!box.isSleeping());
    try std.testing.expect(box.position.y > rest_y + 100);
}

test "sleeping bodies fall when what they rest on is removed, stack included" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    // Gentle gravity: with one velocity pass per step, the upper box of a stack
    // keeps a residual speed of 2*g*dt, which must stay under the sleep threshold.
    var physics = try Physics.init(std.testing.allocator, .{ .gravity = .{ .x = 0, .y = 300 } });
    defer physics.deinit();
    const lower_handle = try world.addDynamicRect(0, -20, 20, 20, .{ .restitution = 0 });
    const upper_handle = try world.addDynamicRect(0, -40.5, 20, 20, .{ .restitution = 0 });
    const floor_handle = try world.addStaticRect(0, 0, 200, 20, .{ .restitution = 0 });
    stepFor(&physics, &world, 3);
    const lower = world.getBody(lower_handle).?;
    const upper = world.getBody(upper_handle).?;
    try std.testing.expect(lower.isSleeping());
    try std.testing.expect(upper.isSleeping());
    const lower_y = lower.position.y;
    const upper_y = upper.position.y;

    // Supported sleepers stay put.
    stepFor(&physics, &world, 1);
    try std.testing.expectEqual(lower_y, lower.position.y);
    try std.testing.expectEqual(upper_y, upper.position.y);

    // Move the floor far away (it is static, so nothing announces the change).
    world.getBody(floor_handle).?.position.y = 100000;
    stepFor(&physics, &world, 1);
    try std.testing.expect(lower.position.y > lower_y + 100);
    try std.testing.expect(upper.position.y > upper_y + 100);
}

test "a zero-mass dynamic body never produces NaN" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    var physics = try Physics.init(std.testing.allocator, .{});
    defer physics.deinit();
    const handle = try world.addDynamicCircle(0, 0, 10, .{ .mass = 0 });
    const other_handle = try world.addDynamicCircle(5, 0, 10, .{});
    _ = try world.addStaticRect(0, 20, 400, 20, .{});
    stepFor(&physics, &world, 1);
    for ([_]World.EntityHandle{ handle, other_handle }) |h| {
        const body = world.getBody(h).?;
        try std.testing.expect(std.math.isFinite(body.position.x) and std.math.isFinite(body.position.y));
        try std.testing.expect(std.math.isFinite(body.velocity.x) and std.math.isFinite(body.velocity.y));
        try std.testing.expect(std.math.isFinite(body.rotation));
    }
}
