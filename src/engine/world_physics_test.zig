const std = @import("std");
const World = @import("World.zig");
const Physics = @import("../physics/Physics.zig");

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
