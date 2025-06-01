const std = @import("std");
const rl = @import("raylib");
const World = @import("world.zig").World;
const Entity = @import("world.zig").Entity;
const ComponentId = @import("world.zig").ComponentId;
const components = @import("components.zig");
const PhysicsWorld = @import("../physics/world.zig").PhysicsWorld;
const PhysicsBodyType = @import("../physics/body.zig").Body;
const PhysicsShape = @import("../core/math/shapes.zig").PhysicsShape;

/// Function signature for systems
pub const SystemFn = *const fn (world: *World, dt: f32) anyerror!void;

/// System schedule that manages execution order of systems
pub const SystemSchedule = struct {
    allocator: std.mem.Allocator,
    systems: std.ArrayList(SystemFn),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .systems = std.ArrayList(SystemFn).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.systems.deinit();
    }

    pub fn addSystem(self: *Self, system: SystemFn) !void {
        try self.systems.append(system);
    }

    pub fn runSystems(self: *Self, world: *World, dt: f32) !void {
        for (self.systems.items) |system| {
            try system(world, dt);
        }
    }

    /// Create a default system schedule with common systems
    pub fn createDefaultSchedule(allocator: std.mem.Allocator) !Self {
        var schedule = Self.init(allocator);

        // Input systems
        try schedule.addSystem(inputUpdateSystem);
        try schedule.addSystem(playerInputSystem);

        // Physics sync system runs AFTER physics world update (called from engine)
        // Note: Real physics simulation happens in engine.update() before systems run
        try schedule.addSystem(physicsSyncFromWorldSystem);

        // Legacy movement system for non-physics entities
        try schedule.addSystem(movementSystem);

        // Game logic systems
        try schedule.addSystem(timerSystem);
        try schedule.addSystem(lifetimeSystem);
        try schedule.addSystem(healthSystem);
        try schedule.addSystem(animationSystem);

        // Rendering systems (order matters!)
        try schedule.addSystem(cameraSystem); // Begin 2D camera mode
        try schedule.addSystem(spriteRenderSystem); // Render sprites
        try schedule.addSystem(shapeRenderSystem); // Render shapes
        try schedule.addSystem(textRenderSystem); // Render text
        try schedule.addSystem(endCameraSystem); // End 2D camera mode

        // Cleanup systems
        try schedule.addSystem(destroySystem);

        return schedule;
    }
};

// ============================================================================
// INPUT SYSTEMS
// ============================================================================

/// Updates input components with current keyboard/mouse state
pub fn inputUpdateSystem(world: *World, dt: f32) !void {
    _ = dt;

    const input_id = world.getComponentId(components.Input) orelse return;
    var query_iter = world.query(&[_]ComponentId{input_id}, &[_]ComponentId{});

    while (query_iter.next()) |entity| {
        if (world.getComponent(components.Input, entity)) |input| {
            // Update movement input
            input.movement.x = 0;
            input.movement.y = 0;

            if (rl.isKeyDown(.w) or rl.isKeyDown(.up)) input.movement.y -= 1;
            if (rl.isKeyDown(.s) or rl.isKeyDown(.down)) input.movement.y += 1;
            if (rl.isKeyDown(.a) or rl.isKeyDown(.left)) input.movement.x -= 1;
            if (rl.isKeyDown(.d) or rl.isKeyDown(.right)) input.movement.x += 1;

            // Clear previous frame actions
            input.actions = 0;
            input.mouse_buttons = 0;

            // Update action inputs (pressed this frame)
            if (rl.isKeyPressed(.space)) {
                input.setAction(.Jump, true, false);
            }
            if (rl.isKeyPressed(.x)) {
                input.setAction(.Attack, true, false);
            }
            if (rl.isKeyPressed(.e)) {
                input.setAction(.Interact, true, false);
            }
            if (rl.isKeyPressed(.escape)) {
                input.setAction(.Menu, true, false);
            }
            if (rl.isKeyPressed(.i)) {
                input.setAction(.Inventory, true, false);
            }

            // Update held actions
            input.setAction(.Jump, rl.isKeyPressed(.space), rl.isKeyDown(.space));
            input.setAction(.Attack, rl.isKeyPressed(.x), rl.isKeyDown(.x));
            input.setAction(.Interact, rl.isKeyPressed(.e), rl.isKeyDown(.e));

            // Update mouse input
            input.mouse_world_pos = rl.getMousePosition();
            if (rl.isMouseButtonPressed(.left)) input.mouse_buttons |= 1;
            if (rl.isMouseButtonPressed(.right)) input.mouse_buttons |= 2;
            if (rl.isMouseButtonPressed(.middle)) input.mouse_buttons |= 4;

            input.mouse_buttons_held = 0;
            if (rl.isMouseButtonDown(.left)) input.mouse_buttons_held |= 1;
            if (rl.isMouseButtonDown(.right)) input.mouse_buttons_held |= 2;
            if (rl.isMouseButtonDown(.middle)) input.mouse_buttons_held |= 4;
        }
    }
}

/// Handles player movement and actions based on input
pub fn playerInputSystem(world: *World, dt: f32) !void {
    _ = dt;

    const player_id = world.getComponentId(components.Player) orelse return;
    const input_id = world.getComponentId(components.Input) orelse return;
    const velocity_id = world.getComponentId(components.Velocity) orelse return;

    var query_iter = world.query(&[_]ComponentId{ player_id, input_id, velocity_id }, &[_]ComponentId{});

    while (query_iter.next()) |entity| {
        if (world.getComponent(components.Player, entity)) |player| {
            if (world.getComponent(components.Input, entity)) |input| {
                if (world.getComponent(components.Velocity, entity)) |velocity| {
                    // Movement
                    velocity.linear.x = input.movement.x * player.move_speed;

                    // Jumping
                    if (input.isActionPressed(.Jump)) {
                        if (player.is_grounded) {
                            velocity.linear.y = -player.jump_force;
                            player.is_grounded = false;
                        } else if (player.can_double_jump and !player.has_used_double_jump) {
                            velocity.linear.y = -player.jump_force;
                            player.has_used_double_jump = true;
                        }
                    }
                }
            }
        }
    }
}

// ============================================================================
// PHYSICS SYSTEMS (Updated to use real physics world)
// ============================================================================

/// Syncs ECS transforms FROM physics world bodies (after physics simulation)
/// This should be called AFTER the physics world has been updated
pub fn physicsSyncFromWorldSystem(world: *World, dt: f32) !void {
    _ = dt;

    // NOTE: This is a placeholder system that shows how physics sync would work
    // The actual syncing is done in engine.syncPhysicsWithTransforms()
    // because it needs access to the physics world reference

    const physics_body_id = world.getComponentId(components.PhysicsBodyRef) orelse return;
    const transform_id = world.getComponentId(components.Transform) orelse return;

    var query_iter = world.query(&[_]ComponentId{ physics_body_id, transform_id }, &[_]ComponentId{});
    var count: u32 = 0;

    while (query_iter.next()) |entity| {
        count += 1;
        _ = entity; // Entity found with physics body and transform
    }

    if (count > 0) {
        std.debug.print("Found {d} physics entities to sync\n", .{count});
    }
}

/// Legacy physics system - now deprecated, kept for backwards compatibility
pub fn physicsSystem(world: *World, dt: f32) !void {
    const rigidbody_id = world.getComponentId(components.RigidBody) orelse return;
    const velocity_id = world.getComponentId(components.Velocity) orelse return;

    var query_iter = world.query(&[_]ComponentId{ rigidbody_id, velocity_id }, &[_]ComponentId{});

    while (query_iter.next()) |entity| {
        if (world.getComponent(components.RigidBody, entity)) |body| {
            if (world.getComponent(components.Velocity, entity)) |velocity| {
                if (!body.is_active or body.body_type != .Dynamic) continue;

                // NO GRAVITY - just keep objects where they are
                // const gravity = rl.Vector2.init(0, 980.0); // DISABLED

                // Apply damping
                velocity.linear.x *= (1.0 - body.linear_damping * dt);
                velocity.linear.y *= (1.0 - body.linear_damping * dt);
                velocity.angular *= (1.0 - body.angular_damping * dt);
            }
        }
    }
}

/// Updates entity positions based on velocity (for non-physics entities)
pub fn movementSystem(world: *World, dt: f32) !void {
    const transform_id = world.getComponentId(components.Transform) orelse return;
    const velocity_id = world.getComponentId(components.Velocity) orelse return;
    const physics_body_id = world.getComponentId(components.PhysicsBodyRef);

    // Only move entities that DON'T have physics bodies (avoid conflicts)
    var query_iter = if (physics_body_id) |physics_id|
        world.query(&[_]ComponentId{ transform_id, velocity_id }, &[_]ComponentId{physics_id})
    else
        world.query(&[_]ComponentId{ transform_id, velocity_id }, &[_]ComponentId{});

    while (query_iter.next()) |entity| {
        if (world.getComponent(components.Transform, entity)) |transform| {
            if (world.getComponent(components.Velocity, entity)) |velocity| {
                transform.position.x += velocity.linear.x * dt;
                transform.position.y += velocity.linear.y * dt;
                transform.rotation += velocity.angular * dt;
            }
        }
    }
}

// ============================================================================
// GAMEPLAY SYSTEMS
// ============================================================================

/// Updates timer components
pub fn timerSystem(world: *World, dt: f32) !void {
    const timer_id = world.getComponentId(components.Timer) orelse return;
    var query_iter = world.query(&[_]ComponentId{timer_id}, &[_]ComponentId{});

    while (query_iter.next()) |entity| {
        if (world.getComponent(components.Timer, entity)) |timer| {
            _ = timer.update(dt);
        }
    }
}

/// Destroys entities when their lifetime expires
pub fn lifetimeSystem(world: *World, dt: f32) !void {
    const lifetime_id = world.getComponentId(components.Lifetime) orelse return;
    var query_iter = world.query(&[_]ComponentId{lifetime_id}, &[_]ComponentId{});

    var entities_to_destroy = std.ArrayList(Entity).init(world.allocator);
    defer entities_to_destroy.deinit();

    while (query_iter.next()) |entity| {
        if (world.getComponent(components.Lifetime, entity)) |lifetime| {
            if (lifetime.update(dt)) {
                try entities_to_destroy.append(entity);
            }
        }
    }

    for (entities_to_destroy.items) |entity| {
        world.despawnEntity(entity);
    }
}

/// Handles health regeneration and invulnerability
pub fn healthSystem(world: *World, dt: f32) !void {
    const health_id = world.getComponentId(components.Health) orelse return;
    var query_iter = world.query(&[_]ComponentId{health_id}, &[_]ComponentId{});

    while (query_iter.next()) |entity| {
        if (world.getComponent(components.Health, entity)) |health| {
            // Update invulnerability
            if (health.is_invulnerable) {
                health.invulnerability_timer -= dt;
                if (health.invulnerability_timer <= 0) {
                    health.is_invulnerable = false;
                }
            }

            // Apply regeneration
            if (health.regeneration_rate > 0) {
                health.heal(health.regeneration_rate * dt);
            }
        }
    }
}

/// Updates sprite animations
pub fn animationSystem(world: *World, dt: f32) !void {
    const animation_id = world.getComponentId(components.Animation) orelse return;
    var query_iter = world.query(&[_]ComponentId{animation_id}, &[_]ComponentId{});

    while (query_iter.next()) |entity| {
        if (world.getComponent(components.Animation, entity)) |animation| {
            _ = animation.update(dt);
        }
    }
}

// ============================================================================
// RENDERING SYSTEMS
// ============================================================================

/// Updates camera for rendering
pub fn cameraSystem(world: *World, dt: f32) !void {
    _ = dt;

    const camera_id = world.getComponentId(components.Camera2D) orelse return;
    const transform_id = world.getComponentId(components.Transform) orelse return;

    var query_iter = world.query(&[_]ComponentId{ camera_id, transform_id }, &[_]ComponentId{});

    while (query_iter.next()) |entity| {
        if (world.getComponent(components.Camera2D, entity)) |camera| {
            if (world.getComponent(components.Transform, entity)) |transform| {
                if (camera.is_main) {
                    const raylib_camera = rl.Camera2D{
                        .target = camera.target,
                        .offset = rl.Vector2.init(
                            @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0 + camera.offset.x,
                            @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0 + camera.offset.y,
                        ),
                        .rotation = camera.rotation * (180.0 / std.math.pi), // Convert to degrees
                        .zoom = camera.zoom,
                    };

                    rl.beginMode2D(raylib_camera);
                    _ = transform;
                    return; // Only set up one main camera
                }
            }
        }
    }
}

/// Ends camera 2D mode after all 2D rendering
pub fn endCameraSystem(world: *World, dt: f32) !void {
    _ = world;
    _ = dt;

    // End 2D camera mode
    rl.endMode2D();
}

/// Renders sprite components
pub fn spriteRenderSystem(world: *World, dt: f32) !void {
    _ = dt;

    const sprite_id = world.getComponentId(components.Sprite) orelse return;
    const transform_id = world.getComponentId(components.Transform) orelse return;

    var query_iter = world.query(&[_]ComponentId{ sprite_id, transform_id }, &[_]ComponentId{});

    var count: u32 = 0;

    while (query_iter.next()) |entity| {
        if (world.getComponent(components.Sprite, entity)) |sprite| {
            if (world.getComponent(components.Transform, entity)) |transform| {
                count += 1;

                const dest_rect = rl.Rectangle{
                    .x = transform.position.x - 16, // Assuming 32x32 sprite
                    .y = transform.position.y - 16,
                    .width = 32,
                    .height = 32,
                };

                // For now, just draw colored rectangles
                if (sprite.texture_id == 0) {
                    rl.drawRectangleRec(dest_rect, sprite.color);
                }
                // TODO: Implement texture rendering when texture system is added
            }
        }
    }

    if (count > 0) {
        std.debug.print("Rendered {d} sprites\n", .{count});
    }
}

/// Renders geometric shapes
pub fn shapeRenderSystem(world: *World, dt: f32) !void {
    _ = dt;

    const shape_id = world.getComponentId(components.Shape) orelse return;
    const transform_id = world.getComponentId(components.Transform) orelse return;

    var query_iter = world.query(&[_]ComponentId{ shape_id, transform_id }, &[_]ComponentId{});

    var count: u32 = 0;
    while (query_iter.next()) |entity| {
        if (world.getComponent(components.Shape, entity)) |shape| {
            if (world.getComponent(components.Transform, entity)) |transform| {
                count += 1;

                switch (shape.shape_type) {
                    .Circle => |circle| {
                        if (circle.filled) {
                            rl.drawCircleV(transform.position, circle.radius, shape.color);
                        } else {
                            rl.drawCircleLinesV(transform.position, circle.radius, shape.color);
                        }
                    },
                    .Rectangle => |rect| {
                        const draw_rect = rl.Rectangle{
                            .x = transform.position.x - rect.width / 2,
                            .y = transform.position.y - rect.height / 2,
                            .width = rect.width,
                            .height = rect.height,
                        };
                        if (rect.filled) {
                            rl.drawRectangleRec(draw_rect, shape.color);
                        } else {
                            rl.drawRectangleLinesEx(draw_rect, 1.0, shape.color);
                        }
                    },
                    .Line => |line| {
                        rl.drawLineEx(transform.position, line.end_pos, line.thickness, shape.color);
                    },
                }
            }
        }
    }

    if (count > 0) {
        std.debug.print("Rendered {d} shapes\n", .{count});
    }
}

/// Renders text components
pub fn textRenderSystem(world: *World, dt: f32) !void {
    _ = dt;

    const text_id = world.getComponentId(components.Text) orelse return;
    const transform_id = world.getComponentId(components.Transform) orelse return;

    var query_iter = world.query(&[_]ComponentId{ text_id, transform_id }, &[_]ComponentId{});

    while (query_iter.next()) |entity| {
        if (world.getComponent(components.Text, entity)) |text| {
            if (world.getComponent(components.Transform, entity)) |transform| {
                const text_slice = text.getText();
                // Convert to null-terminated string for raylib
                var text_buffer: [256:0]u8 = undefined;
                const len = @min(text_slice.len, 255);
                @memcpy(text_buffer[0..len], text_slice[0..len]);
                text_buffer[len] = 0;

                rl.drawText(&text_buffer, @intFromFloat(transform.position.x), @intFromFloat(transform.position.y), @intFromFloat(text.font_size), text.color);
            }
        }
    }
}

// ============================================================================
// CLEANUP SYSTEMS
// ============================================================================

/// Removes entities marked for destruction
pub fn destroySystem(world: *World, dt: f32) !void {
    _ = dt;

    const to_destroy_id = world.getComponentId(components.ToDestroy) orelse return;
    var query_iter = world.query(&[_]ComponentId{to_destroy_id}, &[_]ComponentId{});

    var entities_to_destroy = std.ArrayList(Entity).init(world.allocator);
    defer entities_to_destroy.deinit();

    while (query_iter.next()) |entity| {
        try entities_to_destroy.append(entity);
    }

    for (entities_to_destroy.items) |entity| {
        world.despawnEntity(entity);
    }
}
