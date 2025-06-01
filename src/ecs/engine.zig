const std = @import("std");
const rl = @import("raylib");
const World = @import("world.zig").World;
const Entity = @import("world.zig").Entity;
const ComponentId = @import("world.zig").ComponentId;
const components = @import("components.zig");
const systems = @import("systems.zig");
const SystemSchedule = systems.SystemSchedule;
const GUI = @import("../gui/gui_manager.zig").GUI;
const PhysicsWorld = @import("../physics/world.zig").PhysicsWorld;
const PhysicsConfig = @import("../physics/config.zig").PhysicsConfig;
const PhysicsBodyType = @import("../physics/body.zig").Body;
const PhysicsShape = @import("../core/math/shapes.zig").PhysicsShape;

/// ECS-based game engine
pub const ECSEngine = struct {
    allocator: std.mem.Allocator,
    world: World,
    physics_world: PhysicsWorld,
    schedule: SystemSchedule,
    gui: GUI,
    is_running: bool,
    target_fps: u32,

    // Window settings
    window_width: i32,
    window_height: i32,
    window_title: []const u8,
    last_window_width: i32,
    last_window_height: i32,

    const Self = @This();

    pub const Config = struct {
        window_width: i32 = 800,
        window_height: i32 = 600,
        window_title: []const u8 = "Zixel Game",
        target_fps: u32 = 60,
        enable_gui: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        // Initialize Raylib
        const title_cstr = try allocator.dupeZ(u8, config.window_title);
        defer allocator.free(title_cstr);

        rl.initWindow(config.window_width, config.window_height, title_cstr);
        rl.setTargetFPS(@intCast(config.target_fps));

        // Create physics configuration
        const physics_config = PhysicsConfig{
            .gravity = rl.Vector2{ .x = 0, .y = 981.0 }, // 981 pixels/s^2 downward
            .physics_time_step = 1.0 / 60.0, // 60 FPS physics
            .allow_sleeping = true,
            .debug_draw_aabb = false,
            .debug_draw_contacts = false,
        };

        const world = World.init(allocator);
        const schedule = try SystemSchedule.createDefaultSchedule(allocator);
        const gui = GUI.init(allocator);
        const physics_world = PhysicsWorld.init(allocator, physics_config);

        var engine = Self{
            .allocator = allocator,
            .world = world,
            .physics_world = physics_world,
            .schedule = schedule,
            .gui = gui,
            .is_running = false,
            .target_fps = config.target_fps,
            .window_width = config.window_width,
            .window_height = config.window_height,
            .window_title = config.window_title,
            .last_window_width = config.window_width,
            .last_window_height = config.window_height,
        };

        // Register all components
        try engine.registerComponents();

        return engine;
    }

    pub fn deinit(self: *Self) void {
        self.gui.deinit();
        self.schedule.deinit();
        self.physics_world.deinit();
        self.world.deinit();
        rl.closeWindow();
    }

    /// Check if window was resized
    pub fn isWindowResized(self: *Self) bool {
        const current_width = rl.getScreenWidth();
        const current_height = rl.getScreenHeight();

        if (current_width != self.last_window_width or current_height != self.last_window_height) {
            self.last_window_width = current_width;
            self.last_window_height = current_height;
            return true;
        }
        return false;
    }

    /// Run the main game loop
    pub fn run(self: *Self) !void {
        self.is_running = true;

        while (self.is_running and !rl.windowShouldClose()) {
            const dt = rl.getFrameTime();

            // Handle GUI toggle (F1 key)
            if (rl.isKeyPressed(.f1)) {
                self.gui.toggleVisibility();
            }

            // Update physics world first (separate from ECS)
            self.physics_world.update(dt);

            // Sync physics bodies to ECS transforms
            self.syncPhysicsWithTransforms();

            // Update ECS systems (non-rendering)
            try self.runUpdateSystems(dt);

            // Render
            rl.beginDrawing();
            rl.clearBackground(rl.Color.ray_white);

            // Render systems (inside drawing context)
            try self.runRenderSystems(dt);

            // Render GUI on top
            self.gui.update(self);

            rl.endDrawing();
        }
    }

    /// Run only the update systems (non-rendering)
    fn runUpdateSystems(self: *Self, dt: f32) !void {
        // Input systems
        try systems.inputUpdateSystem(&self.world, dt);
        try systems.playerInputSystem(&self.world, dt);

        // Physics systems
        try systems.physicsSystem(&self.world, dt);
        try systems.movementSystem(&self.world, dt);

        // Game logic systems
        try systems.timerSystem(&self.world, dt);
        try systems.lifetimeSystem(&self.world, dt);
        try systems.healthSystem(&self.world, dt);
        try systems.animationSystem(&self.world, dt);

        // Cleanup systems
        try systems.destroySystem(&self.world, dt);
    }

    /// Run only the rendering systems (inside drawing context)
    fn runRenderSystems(self: *Self, dt: f32) !void {
        // Rendering systems (order matters!)
        try systems.cameraSystem(&self.world, dt); // Begin 2D camera mode
        try systems.spriteRenderSystem(&self.world, dt); // Render sprites
        try systems.shapeRenderSystem(&self.world, dt); // Render shapes
        try systems.textRenderSystem(&self.world, dt); // Render text
        try systems.endCameraSystem(&self.world, dt); // End 2D camera mode
    }

    /// Stop the engine
    pub fn stop(self: *Self) void {
        self.is_running = false;
    }

    /// Create a new entity
    pub fn createEntity(self: *Self) Entity {
        return self.world.spawnEntity();
    }

    /// Destroy an entity
    pub fn destroyEntity(self: *Self, entity: Entity) void {
        self.world.despawnEntity(entity);
    }

    /// Add a component to an entity
    pub fn addComponent(self: *Self, entity: Entity, component: anytype) !void {
        try self.world.addComponent(entity, component);
    }

    /// Get a component from an entity
    pub fn getComponent(self: *Self, comptime T: type, entity: Entity) ?*T {
        return self.world.getComponent(T, entity);
    }

    /// Remove a component from an entity
    pub fn removeComponent(self: *Self, comptime T: type, entity: Entity) !void {
        try self.world.removeComponent(T, entity);
    }

    /// Add a custom system to the schedule
    pub fn addSystem(self: *Self, system: systems.SystemFn) !void {
        try self.schedule.addSystem(system);
    }

    /// Get access to the ECS world
    pub fn getWorld(self: *Self) *World {
        return &self.world;
    }

    /// Get the physics world for direct access
    pub fn getPhysicsWorld(self: *Self) *PhysicsWorld {
        return &self.physics_world;
    }

    /// Get the current number of entities
    pub fn getEntityCount(self: *Self) u32 {
        var count: u32 = 0;
        for (self.world.archetypes.items) |*archetype| {
            count += @intCast(archetype.index_to_entity.items.len);
        }
        return count;
    }

    /// Register all components
    fn registerComponents(self: *Self) !void {
        // Create temporary entities just to register component types
        const temp_entities = [_]Entity{
            self.createEntity(), self.createEntity(), self.createEntity(), self.createEntity(),
            self.createEntity(), self.createEntity(), self.createEntity(), self.createEntity(),
            self.createEntity(), self.createEntity(), self.createEntity(), self.createEntity(),
            self.createEntity(), self.createEntity(), self.createEntity(), self.createEntity(),
        };

        // Register basic components
        try self.addComponent(temp_entities[0], components.Transform{});
        try self.addComponent(temp_entities[1], components.Velocity{});
        try self.addComponent(temp_entities[2], components.RigidBody{}); // Use default values
        try self.addComponent(temp_entities[3], components.Collider.rectangle(32, 48));
        try self.addComponent(temp_entities[4], components.Sprite.fromColor(rl.Color.blue));
        try self.addComponent(temp_entities[5], components.Player{
            .move_speed = 200.0,
            .jump_force = 400.0,
        });
        try self.addComponent(temp_entities[6], components.Input{});
        try self.addComponent(temp_entities[7], components.Health.init(100.0));
        try self.addComponent(temp_entities[8], components.Tag{});

        // Register physics components
        try self.addComponent(temp_entities[9], components.PhysicsBodyRef.init(0));
        try self.addComponent(temp_entities[10], components.Shape.circle(16, true));
        try self.addComponent(temp_entities[11], components.Lifetime.init(10.0));

        // Register AI components
        try self.addComponent(temp_entities[12], components.AI{
            .behavior = .Patrol,
            .move_speed = 50.0,
            .detection_radius = 100.0,
        });

        // Register shape and text components
        try self.addComponent(temp_entities[13], components.Shape.rectangle(32, 48, true));
        try self.addComponent(temp_entities[14], components.Text{
            .font_size = 20.0,
        });

        // Register camera components
        try self.addComponent(temp_entities[15], components.Camera2D.main(rl.Vector2.init(0, 0)));

        // Clean up temporary entities
        for (temp_entities) |entity| {
            self.world.despawnEntity(entity);
        }
    }

    // ========================================================================
    // CONVENIENCE METHODS FOR COMMON ENTITY CREATION
    // ========================================================================

    /// Create a player entity with common components
    pub fn createPlayer(self: *Self, position: rl.Vector2) !Entity {
        const entity = self.createEntity();

        try self.addComponent(entity, components.Transform{
            .position = position,
        });

        try self.addComponent(entity, components.Velocity{});

        try self.addComponent(entity, components.RigidBody.dynamic(1.0));

        try self.addComponent(entity, components.Collider.rectangle(32, 48));

        try self.addComponent(entity, components.Sprite.fromColor(rl.Color.blue));

        try self.addComponent(entity, components.Player{
            .move_speed = 200.0,
            .jump_force = 400.0,
        });

        try self.addComponent(entity, components.Input{});

        try self.addComponent(entity, components.Health.init(100.0));

        var tag = components.Tag{};
        tag.add(.Player);
        try self.addComponent(entity, tag);

        return entity;
    }

    /// Create platform (static rectangular physics body) - UPDATED WITH PHYSICS
    pub fn createPlatform(self: *Self, position: rl.Vector2, size: rl.Vector2) !Entity {
        const transform = components.Transform{
            .position = position,
            .rotation = 0.0,
            .scale = rl.Vector2.init(1.0, 1.0),
        };

        const shape = PhysicsShape{ .rectangle = rl.Rectangle{ .x = 0, .y = 0, .width = size.x, .height = size.y } };
        const entity = try self.createPhysicsEntity(transform, shape, true);

        // Add visual shape with platform color
        var shape_comp = components.Shape.rectangle(size.x, size.y, true);
        shape_comp.color = rl.Color.dark_gray;
        try self.addComponent(entity, shape_comp);

        return entity;
    }

    /// Create an enemy entity
    pub fn createEnemy(self: *Self, position: rl.Vector2) !Entity {
        const entity = self.createEntity();

        try self.addComponent(entity, components.Transform{
            .position = position,
        });

        try self.addComponent(entity, components.Velocity{});

        try self.addComponent(entity, components.RigidBody.dynamic(0.8));

        try self.addComponent(entity, components.Collider.rectangle(24, 32));

        try self.addComponent(entity, components.Sprite.fromColor(rl.Color.red));

        try self.addComponent(entity, components.AI{
            .behavior = .Patrol,
            .move_speed = 50.0,
            .detection_radius = 100.0,
        });

        try self.addComponent(entity, components.Health.init(50.0));

        var tag = components.Tag{};
        tag.add(.Enemy);
        try self.addComponent(entity, tag);

        return entity;
    }

    /// Create a collectible item
    pub fn createCollectible(self: *Self, position: rl.Vector2, lifetime: f32) !Entity {
        const entity = self.createEntity();

        try self.addComponent(entity, components.Transform{
            .position = position,
        });

        try self.addComponent(entity, components.Collider.circle(16));

        var shape = components.Shape.circle(16, true);
        shape.color = rl.Color.gold;
        try self.addComponent(entity, shape);

        try self.addComponent(entity, components.Lifetime.init(lifetime));

        var tag = components.Tag{};
        tag.add(.Collectible);
        try self.addComponent(entity, tag);

        return entity;
    }

    /// Create a projectile entity
    pub fn createProjectile(self: *Self, position: rl.Vector2, velocity: rl.Vector2, lifetime: f32) !Entity {
        const entity = self.createEntity();

        try self.addComponent(entity, components.Transform{
            .position = position,
        });

        try self.addComponent(entity, components.Velocity{
            .linear = velocity,
        });

        try self.addComponent(entity, components.RigidBody{
            .body_type = .Kinematic,
            .gravity_scale = 0.0,
        });

        try self.addComponent(entity, components.Collider.circle(4));

        var shape = components.Shape.circle(4, true);
        shape.color = rl.Color.yellow;
        try self.addComponent(entity, shape);

        try self.addComponent(entity, components.Lifetime.init(lifetime));

        var tag = components.Tag{};
        tag.add(.Projectile);
        try self.addComponent(entity, tag);

        return entity;
    }

    /// Create a camera entity
    pub fn createCamera(self: *Self, target: rl.Vector2) !Entity {
        const entity = self.createEntity();

        try self.addComponent(entity, components.Transform{
            .position = rl.Vector2.init(0, 0),
        });

        try self.addComponent(entity, components.Camera2D.main(target));

        return entity;
    }

    /// Create a text entity
    pub fn createText(self: *Self, position: rl.Vector2, text: []const u8, font_size: f32) !Entity {
        const entity = self.createEntity();

        try self.addComponent(entity, components.Transform{
            .position = position,
        });

        var text_component = components.Text{
            .font_size = font_size,
        };
        text_component.setText(text);
        try self.addComponent(entity, text_component);

        return entity;
    }

    // ========================================================================
    // UTILITY METHODS
    // ========================================================================

    /// Find the first entity with a specific tag
    pub fn findEntityWithTag(self: *Self, tag: components.Tag.TagType) ?Entity {
        const tag_id = self.world.getComponentId(components.Tag) orelse return null;

        var query_iter = self.world.query(&[_]@TypeOf(tag_id){tag_id}, &[_]@TypeOf(tag_id){});

        while (query_iter.next()) |entity| {
            if (self.getComponent(components.Tag, entity)) |entity_tag| {
                if (entity_tag.has(tag)) {
                    return entity;
                }
            }
        }

        return null;
    }

    /// Get all entities with a specific tag
    pub fn findEntitiesWithTag(self: *Self, tag: components.Tag.TagType, allocator: std.mem.Allocator) !std.ArrayList(Entity) {
        var entities = std.ArrayList(Entity).init(allocator);

        const tag_id = self.world.getComponentId(components.Tag) orelse return entities;

        var query_iter = self.world.query(&[_]@TypeOf(tag_id){tag_id}, &[_]@TypeOf(tag_id){});

        while (query_iter.next()) |entity| {
            if (self.getComponent(components.Tag, entity)) |entity_tag| {
                if (entity_tag.has(tag)) {
                    try entities.append(entity);
                }
            }
        }

        return entities;
    }

    /// Get window dimensions
    pub fn getWindowSize(self: *const Self) rl.Vector2 {
        return rl.Vector2.init(@floatFromInt(self.window_width), @floatFromInt(self.window_height));
    }

    /// Update the engine
    pub fn update(self: *Self, dt: f32) !void {
        if (!self.is_running) return;

        // Update physics world first
        self.physics_world.update(dt);

        // Run ECS systems
        try self.schedule.runSystems(&self.world, dt);

        // Update GUI
        self.gui.update(self);
    }

    /// Toggle GUI visibility
    pub fn toggleGUI(self: *Self) void {
        self.gui.toggleVisibility();
    }

    /// Create a physics body and attach it to an entity
    pub fn createPhysicsEntity(self: *Self, transform: components.Transform, shape: PhysicsShape, is_static: bool) !Entity {
        const entity = self.createEntity();

        // Add transform component
        try self.addComponent(entity, transform);

        // Create physics body
        const physics_body = if (is_static)
            PhysicsBodyType.initStatic(shape, transform.position, .{})
        else
            PhysicsBodyType.initDynamic(shape, transform.position, .{});

        // Add to physics world
        const body_id = try self.physics_world.addBody(physics_body);

        // Add physics body reference component
        try self.addComponent(entity, components.PhysicsBodyRef.init(body_id));

        return entity;
    }

    /// Create a dynamic physics object
    pub fn createDynamicObject(self: *Self, position: rl.Vector2, shape: PhysicsShape) !Entity {
        const transform = components.Transform{
            .position = position,
            .rotation = 0.0,
            .scale = rl.Vector2.init(1.0, 1.0),
        };

        const entity = try self.createPhysicsEntity(transform, shape, false);

        // Add visual representation based on shape WITH COLORS
        switch (shape) {
            .circle => |circle| {
                var visual_shape = components.Shape.circle(circle.radius, true);
                visual_shape.color = rl.Color.blue; // Make circles blue
                try self.addComponent(entity, visual_shape);
            },
            .rectangle => |rect| {
                var visual_shape = components.Shape.rectangle(rect.width, rect.height, true);
                visual_shape.color = rl.Color.red; // Make rectangles red
                try self.addComponent(entity, visual_shape);
            },
        }

        std.debug.print("Created dynamic physics object at ({d:.1}, {d:.1})\n", .{ position.x, position.y });
        return entity;
    }

    /// Sync physics bodies with transform components
    pub fn syncPhysicsWithTransforms(self: *Self) void {
        const physics_body_id = self.world.getComponentId(components.PhysicsBodyRef) orelse return;
        const transform_id = self.world.getComponentId(components.Transform) orelse return;

        var query_iter = self.world.query(&[_]ComponentId{ physics_body_id, transform_id }, &[_]ComponentId{});

        while (query_iter.next()) |entity| {
            if (self.world.getComponent(components.PhysicsBodyRef, entity)) |physics_ref| {
                if (self.world.getComponent(components.Transform, entity)) |transform| {
                    physics_ref.syncToTransform(&self.physics_world, transform);
                }
            }
        }
    }
};
