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
const InputManager = @import("../input/input_manager.zig").InputManager;

pub const Engine = struct {
    allocator: std.mem.Allocator,
    world: World,
    physics_world: PhysicsWorld,
    schedule: SystemSchedule,
    gui: GUI,
    is_running: bool,
    target_fps: u32,
    input_manager: InputManager,
    input_context: InputContext = .Game,

    // Window settings
    window_width: i32,
    window_height: i32,
    window_title: []const u8,
    last_window_width: i32,
    last_window_height: i32,

    const Self = @This();

    const InputContext = enum { Game, GUI, Menu, Paused };

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
            .gravity = rl.Vector2{ .x = 0, .y = 300 },
            .physics_time_step = 1.0 / 60.0,
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
            .input_manager = InputManager.init(),
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
        self.input_manager.deinit();
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

        while (self.shouldRun()) {
            const dt = rl.getFrameTime();

            // Update physics world first (separate from ECS)
            self.physics_world.update(dt);

            // Sync physics bodies to ECS transforms
            self.syncPhysicsWithTransforms();

            // Run the custom system schedule (for update systems + custom systems)
            try self.schedule.runSystems(&self.world, dt);

            // Render
            rl.beginDrawing();
            rl.clearBackground(rl.Color.ray_white);

            // Render systems (inside drawing context) - these must be here!
            try self.runRenderSystems(dt);

            // Render GUI on top
            self.gui.update(self);

            rl.endDrawing();
        }
    }

    fn handleGUIInput(self: *Self) void {
        // GUI toggle (F1) - always works regardless of context
        if (self.input_manager.isKeyPressed(.f1)) {
            self.gui.toggleVisibility();

            // Update context based on GUI state
            if (self.gui.isVisible()) {
                self.setInputContext(.gui);
            } else {
                self.setInputContext(.game);
            }
        }

        // ESC to close GUI (only when GUI is open)
        if (self.input_context == .gui and self.input_manager.isKeyPressed(.escape)) {
            self.gui.setVisible(false);
            self.setInputContext(.game);
        }
    }

    fn handleGameInput(self: *Self, dt: f32) !void {
        switch (self.input_context) {
            .game => {
                // Normal gameplay - run input systems
                try systems.inputSystem(&self.world, dt, &self.input_manager);
                try systems.physicsInputSystem(&self.world, dt, &self.physics_world);
            },
            .gui => {
                // GUI is open - block game input
                // (Do nothing - game input systems don't run)
            },
            .menu => {
                // In menu - handle menu navigation
                // try systems.menuInputSystem(&self.world, dt, &self.input_manager);
            },
            .paused => {
                // Game paused - only allow unpause input
                if (self.input_manager.isKeyPressed(.p)) {
                    self.setInputContext(.game);
                }
            },
        }
    }

    // TODO: Implement menu input system
    fn handleMenuInput(self: *Self, dt: f32) !void {
        // In menu - handle menu navigation
        // try systems.menuInputSystem(&self.world, dt, &self.input_manager);
        _ = dt;
        _ = self;
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

    /// Start the engine (sets running state to true)
    pub fn start(self: *Self) void {
        self.is_running = true;
    }

    pub fn setInputContext(self: *Self, context: InputContext) void {
        self.input_context = context;
    }

    pub fn getInputContext(self: *Self) InputContext {
        return self.input_context;
    }

    /// Check if the engine should continue running (combines internal state with window close check)
    pub fn shouldRun(self: *const Self) bool {
        return self.is_running and !rl.windowShouldClose();
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

    /// Register all components using comptime reflection
    fn registerComponents(self: *Self) !void {
        // Define all component types at comptime
        const ComponentTypes = .{
            components.Transform,
            components.Velocity,
            components.PhysicsBodyRef,
            components.Shape,
            components.Text,
            components.Tag,
            components.ToDestroy,
            components.Camera2D,
            components.Input,
        };

        // Register each component type using comptime iteration
        inline for (ComponentTypes) |ComponentType| {
            _ = try self.world.registerComponent(ComponentType);
        }
    }

    /// Find the first entity with a specific tag
    pub fn findEntityWithTag(self: *Self, tag: components.Tag.TagType) ?Entity {
        const tag_id = components.ComponentType.getId(components.Tag).toU32();

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

        const tag_id = components.ComponentType.getId(components.Tag).toU32();

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

    /// Create a static physics body (can't move, like walls and platforms)
    pub fn createStaticBody(self: *Self, transform: components.Transform, shape: PhysicsShape, color: ?rl.Color) !Entity {
        const entity = self.createEntity();
        try self.addComponent(entity, transform);

        const physics_body = PhysicsBodyType.initStatic(shape, transform.position, .{
            .rotation = transform.rotation,
        });
        const body_id = try self.physics_world.addBody(physics_body);
        try self.addComponent(entity, components.PhysicsBodyRef.init(body_id));

        // Automatically add visual component
        if (color) |c| {
            var visual = switch (shape) {
                .rectangle => |rect| components.Shape.rectangle(rect.width, rect.height, true),
                .circle => |circle| components.Shape.circle(circle.radius, true),
            };
            visual.color = c;
            try self.addComponent(entity, visual);
        }

        return entity;
    }

    /// Create a dynamic physics body (affected by gravity and forces, like balls and boxes)
    pub fn createDynamicBody(self: *Self, transform: components.Transform, shape: PhysicsShape, color: ?rl.Color) !Entity {
        const entity = self.createEntity();
        try self.addComponent(entity, transform);

        const physics_body = PhysicsBodyType.initDynamic(shape, transform.position, .{
            .rotation = transform.rotation,
        });
        const body_id = try self.physics_world.addBody(physics_body);
        try self.addComponent(entity, components.PhysicsBodyRef.init(body_id));

        // Automatically add visual component
        if (color) |c| {
            var visual = switch (shape) {
                .rectangle => |rect| components.Shape.rectangle(rect.width, rect.height, true),
                .circle => |circle| components.Shape.circle(circle.radius, true),
            };
            visual.color = c;
            try self.addComponent(entity, visual);
        }

        return entity;
    }

    /// Create a kinematic physics body (move under direct control, like player paddles)
    pub fn createKinematicBody(self: *Self, transform: components.Transform, shape: PhysicsShape, color: ?rl.Color) !Entity {
        const entity = self.createEntity();
        try self.addComponent(entity, transform);

        const physics_body = PhysicsBodyType.initKinematic(shape, transform.position, .{
            .rotation = transform.rotation,
        });
        const body_id = try self.physics_world.addBody(physics_body);
        try self.addComponent(entity, components.PhysicsBodyRef.init(body_id));

        // Automatically add visual component
        if (color) |c| {
            var visual = switch (shape) {
                .rectangle => |rect| components.Shape.rectangle(rect.width, rect.height, true),
                .circle => |circle| components.Shape.circle(circle.radius, true),
            };
            visual.color = c;
            try self.addComponent(entity, visual);
        }

        return entity;
    }

    /// Sync physics bodies with transform components
    pub fn syncPhysicsWithTransforms(self: *Self) void {
        const physics_body_id = components.ComponentType.getId(components.PhysicsBodyRef).toU32();
        const transform_id = components.ComponentType.getId(components.Transform).toU32();

        var query_iter = self.world.query(&[_]ComponentId{ physics_body_id, transform_id }, &[_]ComponentId{});

        while (query_iter.next()) |entity| {
            if (self.world.getComponent(components.PhysicsBodyRef, entity)) |physics_ref| {
                if (self.world.getComponent(components.Transform, entity)) |transform| {
                    physics_ref.syncToTransform(&self.physics_world, transform);
                }
            }
        }
    }

    /// Create platform (static rectangular physics body) - convenience method
    pub fn createPlatform(self: *Self, position: rl.Vector2, size: rl.Vector2) !Entity {
        const transform = components.Transform{
            .position = position,
            .rotation = 0.0,
            .scale = rl.Vector2.init(1.0, 1.0),
        };

        const shape = PhysicsShape{ .rectangle = rl.Rectangle{ .x = 0, .y = 0, .width = size.x, .height = size.y } };
        return try self.createStaticBody(transform, shape, rl.Color.dark_gray);
    }

    /// Create kinematic entity (for backwards compatibility with examples)
    pub fn createKinematicEntity(self: *Self, transform: components.Transform, shape: PhysicsShape) !Entity {
        return try self.createKinematicBody(transform, shape, null);
    }

    /// Create physics entity (backwards compatibility - use createStaticBody/createDynamicBody instead)
    pub fn createPhysicsEntity(self: *Self, transform: components.Transform, shape: PhysicsShape, is_static: bool) !Entity {
        if (is_static) {
            return try self.createStaticBody(transform, shape, null);
        } else {
            return try self.createDynamicBody(transform, shape, null);
        }
    }

    /// Create physics entity with specific type (backwards compatibility)
    pub fn createPhysicsEntityWithType(self: *Self, transform: components.Transform, shape: PhysicsShape, body_type: enum { Static, Dynamic, Kinematic }) !Entity {
        switch (body_type) {
            .Static => return try self.createStaticBody(transform, shape, null),
            .Dynamic => return try self.createDynamicBody(transform, shape, null),
            .Kinematic => return try self.createKinematicBody(transform, shape, null),
        }
    }

    /// Create dynamic object (backwards compatibility)
    pub fn createDynamicObject(self: *Self, position: rl.Vector2, shape: PhysicsShape) !Entity {
        const transform = components.Transform{ .position = position };
        return try self.createDynamicBody(transform, shape, null);
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

    /// Create a camera entity (simplified - just creates an entity with Transform)
    pub fn createCamera(self: *Self, target: rl.Vector2) !Entity {
        const entity = self.createEntity();

        try self.addComponent(entity, components.Transform{
            .position = target,
        });

        return entity;
    }

    /// Create a minimal player entity (stub for compatibility)
    pub fn createPlayer(self: *Self, position: rl.Vector2) !Entity {
        const entity = self.createEntity();

        try self.addComponent(entity, components.Transform{
            .position = position,
        });

        var shape = components.Shape.rectangle(32, 48, true);
        shape.color = rl.Color.blue;
        try self.addComponent(entity, shape);

        var tag = components.Tag{};
        tag.add(.Player);
        try self.addComponent(entity, tag);

        return entity;
    }

    /// Create a minimal enemy entity (stub for compatibility)
    pub fn createEnemy(self: *Self, position: rl.Vector2) !Entity {
        const entity = self.createEntity();

        try self.addComponent(entity, components.Transform{
            .position = position,
        });

        var shape = components.Shape.rectangle(24, 32, true);
        shape.color = rl.Color.red;
        try self.addComponent(entity, shape);

        var tag = components.Tag{};
        tag.add(.Enemy);
        try self.addComponent(entity, tag);

        return entity;
    }

    /// Create a minimal collectible entity (stub for compatibility)
    pub fn createCollectible(self: *Self, position: rl.Vector2, lifetime: f32) !Entity {
        _ = lifetime; // Ignore lifetime since we don't have Lifetime component
        const entity = self.createEntity();

        try self.addComponent(entity, components.Transform{
            .position = position,
        });

        var shape = components.Shape.circle(16, true);
        shape.color = rl.Color.gold;
        try self.addComponent(entity, shape);

        var tag = components.Tag{};
        tag.add(.Collectible);
        try self.addComponent(entity, tag);

        return entity;
    }
};
