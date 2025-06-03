const std = @import("std");
const rl = @import("raylib");
const World = @import("world.zig").World;
const Entity = @import("world.zig").Entity;
const ComponentId = @import("world.zig").ComponentId;
const components = @import("components.zig");
const PhysicsWorld = @import("../physics/world.zig").PhysicsWorld;
const PhysicsBodyType = @import("../physics/body.zig").Body;
const PhysicsShape = @import("../core/math/shapes.zig").PhysicsShape;
const InputManager = @import("../input/input_manager.zig").InputManager;

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

        // Legacy movement system for non-physics entities
        try schedule.addSystem(movementSystem);

        return schedule;
    }
};

/// Legacy movement system for entities with Velocity but no physics
pub fn movementSystem(world: *World, dt: f32) !void {
    const transform_id = components.ComponentType.getId(components.Transform).toU32();
    const velocity_id = components.ComponentType.getId(components.Velocity).toU32();

    var query_iter = world.query(&[_]ComponentId{ transform_id, velocity_id }, &[_]ComponentId{});

    while (query_iter.next()) |entity| {
        // Skip entities that have physics bodies (they're handled by the physics system)
        if (world.getComponent(components.PhysicsBodyRef, entity) != null) {
            continue;
        }

        if (world.getComponent(components.Transform, entity)) |transform| {
            if (world.getComponent(components.Velocity, entity)) |velocity| {
                transform.position.x += velocity.linear.x * dt;
                transform.position.y += velocity.linear.y * dt;
                transform.rotation += velocity.angular * dt;
            }
        }
    }
}

/// Camera system - sets up 2D camera for rendering
pub fn cameraSystem(world: *World, dt: f32) !void {
    _ = world;
    _ = dt;

    // Simple camera with no offset - objects appear at their actual coordinates
    const camera = rl.Camera2D{
        .target = rl.Vector2.init(0, 0),
        .offset = rl.Vector2.init(0, 0),
        .rotation = 0.0,
        .zoom = 1.0,
    };

    rl.beginMode2D(camera);
}

/// End camera system - ends 2D camera mode
pub fn endCameraSystem(world: *World, dt: f32) !void {
    _ = world;
    _ = dt;
    rl.endMode2D();
}

/// Sprite rendering system
pub fn spriteRenderSystem(world: *World, dt: f32) !void {
    _ = dt;
    // Note: Sprite component was removed, so this system is now empty
    // Left here for potential future sprite implementation
    _ = world;
}

/// Shape rendering system
pub fn shapeRenderSystem(world: *World, dt: f32) !void {
    _ = dt;

    const transform_id = components.ComponentType.getId(components.Transform).toU32();
    const shape_id = components.ComponentType.getId(components.Shape).toU32();

    var query_iter = world.query(&[_]ComponentId{ transform_id, shape_id }, &[_]ComponentId{});

    while (query_iter.next()) |entity| {
        if (world.getComponent(components.Transform, entity)) |transform| {
            if (world.getComponent(components.Shape, entity)) |shape| {
                const pos = transform.position;

                switch (shape.shape_type) {
                    .Circle => |circle| {
                        if (circle.filled) {
                            rl.drawCircleV(pos, circle.radius, shape.color);
                        } else {
                            rl.drawCircleLinesV(pos, circle.radius, shape.color);
                        }
                    },
                    .Rectangle => |rect| {
                        const dest_rect = rl.Rectangle{
                            .x = transform.position.x,
                            .y = transform.position.y,
                            .width = rect.width,
                            .height = rect.height,
                        };
                        const origin = rl.Vector2{ .x = rect.width / 2.0, .y = rect.height / 2.0 };
                        const rotation_degrees = transform.rotation * 180.0 / std.math.pi; // Convert radians to degrees

                        if (rect.filled) {
                            rl.drawRectanglePro(dest_rect, origin, rotation_degrees, shape.color);
                        } else {
                            // For non-filled rectangles, we need to draw rotated lines
                            const half_w = rect.width / 2.0;
                            const half_h = rect.height / 2.0;
                            const cos_r = @cos(transform.rotation);
                            const sin_r = @sin(transform.rotation);

                            const corners = [4]rl.Vector2{
                                rl.Vector2{ .x = transform.position.x + (-half_w * cos_r - -half_h * sin_r), .y = transform.position.y + (-half_w * sin_r + -half_h * cos_r) },
                                rl.Vector2{ .x = transform.position.x + (half_w * cos_r - -half_h * sin_r), .y = transform.position.y + (half_w * sin_r + -half_h * cos_r) },
                                rl.Vector2{ .x = transform.position.x + (half_w * cos_r - half_h * sin_r), .y = transform.position.y + (half_w * sin_r + half_h * cos_r) },
                                rl.Vector2{ .x = transform.position.x + (-half_w * cos_r - half_h * sin_r), .y = transform.position.y + (-half_w * sin_r + half_h * cos_r) },
                            };

                            for (0..4) |i| {
                                const next = (i + 1) % 4;
                                rl.drawLineV(corners[i], corners[next], shape.color);
                            }
                        }
                    },
                    .Line => |line| {
                        rl.drawLineEx(pos, line.end_pos, line.thickness, shape.color);
                    },
                }
            }
        }
    }
}

/// Text rendering system
pub fn textRenderSystem(world: *World, dt: f32) !void {
    _ = dt;

    const transform_id = components.ComponentType.getId(components.Transform).toU32();
    const text_id = components.ComponentType.getId(components.Text).toU32();

    var query_iter = world.query(&[_]ComponentId{ transform_id, text_id }, &[_]ComponentId{});

    while (query_iter.next()) |entity| {
        if (world.getComponent(components.Transform, entity)) |transform| {
            if (world.getComponent(components.Text, entity)) |text| {
                const text_str = text.getText();
                if (text_str.len > 0) {
                    const text_size = rl.measureText(@ptrCast(text_str), @intFromFloat(text.font_size));
                    const draw_pos = rl.Vector2.init(
                        transform.position.x - @as(f32, @floatFromInt(text_size)) / 2,
                        transform.position.y - text.font_size / 2,
                    );
                    rl.drawText(@ptrCast(text_str), @intFromFloat(draw_pos.x), @intFromFloat(draw_pos.y), @intFromFloat(text.font_size), text.color);
                }
            }
        }
    }
}

pub fn inputSystem(world: *World, dt: f32, input_manager: *InputManager) !void {
    const input_id = components.ComponentType.getId(components.Input).toU32();
    var query_iter = world.query(&[_]ComponentId{input_id}, &[_]ComponentId{});

    while (query_iter.next()) |entity| {
        if (world.getComponent(components.Input, entity)) |input| {
            // Read keyboard input using InputManager
            input.move_left = input_manager.isKeyDown(.a) or input_manager.isKeyDown(.left);
            input.move_right = input_manager.isKeyDown(.d) or input_manager.isKeyDown(.right);
            input.move_up = input_manager.isKeyDown(.w) or input_manager.isKeyDown(.up);
            input.move_down = input_manager.isKeyDown(.s) or input_manager.isKeyDown(.down);

            // Handle jump with buffering
            if (input_manager.isKeyPressed(.space)) {
                input.jump = true;
                input.jump_buffer_time = input.jump_buffer_max;
            } else {
                input.jump = false;
                if (input.jump_buffer_time > 0) {
                    input.jump_buffer_time -= dt;
                }
            }
        }
    }
}

pub fn physicsInputSystem(world: *World, dt: f32, physics_world: *PhysicsWorld) !void {
    const input_id = components.ComponentType.getId(components.Input).toU32();
    const physics_id = components.ComponentType.getId(components.PhysicsBodyRef).toU32();

    // Find entities with BOTH Input AND PhysicsBodyRef components
    var query_iter = world.query(&[_]ComponentId{ input_id, physics_id }, &[_]ComponentId{});

    while (query_iter.next()) |entity| {
        if (world.getComponent(components.Input, entity)) |input| {
            if (world.getComponent(components.PhysicsBodyRef, entity)) |physics_ref| {
                if (physics_ref.getBody(physics_world)) |body| {
                    // Apply horizontal movement forces
                    var force_x: f32 = 0;
                    if (input.move_left) force_x -= input.move_speed;
                    if (input.move_right) force_x += input.move_speed;

                    if (force_x != 0) {
                        body.applyForce(rl.Vector2{ .x = force_x, .y = 0 });
                    }

                    // Handle jump (using velocity modification since no applyImpulse)
                    if (input.jump or input.jump_buffer_time > 0) {
                        const velocity = body.getVelocity();
                        // Simple ground check: only jump if not moving up fast
                        if (velocity.y > -50.0) {
                            // Directly set upward velocity for jump
                            body.setVelocity(rl.Vector2{ .x = velocity.x, .y = -input.jump_force });
                            input.jump_buffer_time = 0; // Clear jump buffer
                        }
                    }
                }
            }
        }
    }
    _ = dt; // Mark unused parameter
}
