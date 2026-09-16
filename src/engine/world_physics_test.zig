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
