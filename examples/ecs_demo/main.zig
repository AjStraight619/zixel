const std = @import("std");
const zixel = @import("zixel");
const rl = zixel.rl;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the ECS engine
    var engine = try zixel.ECSEngine.init(allocator, .{
        .window_width = 1024,
        .window_height = 768,
        .window_title = "Zixel ECS Demo",
        .target_fps = 60,
    });
    defer engine.deinit();

    // Create game entities
    try setupGame(&engine);

    // Run the game loop
    try engine.run();
}

fn setupGame(engine: *zixel.ECSEngine) !void {
    // Create a camera
    _ = try engine.createCamera(rl.Vector2.init(400, 300));

    // Create the player
    _ = try engine.createPlayer(rl.Vector2.init(100, 500));

    // Create some platforms
    _ = try engine.createPlatform(rl.Vector2.init(400, 600), rl.Vector2.init(800, 50)); // Ground
    _ = try engine.createPlatform(rl.Vector2.init(200, 450), rl.Vector2.init(150, 20)); // Platform 1
    _ = try engine.createPlatform(rl.Vector2.init(600, 350), rl.Vector2.init(150, 20)); // Platform 2
    _ = try engine.createPlatform(rl.Vector2.init(400, 250), rl.Vector2.init(100, 20)); // Platform 3

    // Create some enemies
    _ = try engine.createEnemy(rl.Vector2.init(300, 400));
    _ = try engine.createEnemy(rl.Vector2.init(700, 300));

    // Create some collectibles
    _ = try engine.createCollectible(rl.Vector2.init(250, 400), 30.0); // Disappears after 30 seconds
    _ = try engine.createCollectible(rl.Vector2.init(650, 300), 30.0);
    _ = try engine.createCollectible(rl.Vector2.init(400, 200), 30.0);

    // Create UI text
    _ = try engine.createText(rl.Vector2.init(10, 10), "Zixel ECS Demo", 24);
    _ = try engine.createText(rl.Vector2.init(10, 40), "WASD/Arrow Keys: Move", 16);
    _ = try engine.createText(rl.Vector2.init(10, 60), "Space: Jump", 16);
    _ = try engine.createText(rl.Vector2.init(10, 80), "X: Attack", 16);
    _ = try engine.createText(rl.Vector2.init(10, 100), "E: Interact", 16);

    // Add a custom system for projectile shooting
    try engine.addSystem(projectileShootingSystem);

    // Add collision detection system
    try engine.addSystem(collisionSystem);
}

/// Custom system for shooting projectiles
fn projectileShootingSystem(world: *zixel.World, dt: f32) !void {
    _ = dt;

    const player_id = world.getComponentId(zixel.components.Player) orelse return;
    const transform_id = world.getComponentId(zixel.components.Transform) orelse return;
    const input_id = world.getComponentId(zixel.components.Input) orelse return;

    var query_iter = world.query(&[_]@TypeOf(player_id){ player_id, transform_id, input_id }, &[_]@TypeOf(player_id){});

    while (query_iter.next()) |entity| {
        if (world.getComponent(zixel.components.Transform, entity)) |transform| {
            if (world.getComponent(zixel.components.Input, entity)) |input| {
                if (input.isActionPressed(.Attack)) {
                    // Shoot a projectile towards the mouse
                    const projectile_pos = rl.Vector2.init(transform.position.x, transform.position.y - 20);

                    // Calculate direction towards mouse (simplified - just shoot right)
                    const projectile_velocity = rl.Vector2.init(300, 0);

                    // Create projectile (this would need access to the engine, so we'll skip for now)
                    // This demonstrates how you might extend the system
                    _ = projectile_pos;
                    _ = projectile_velocity;
                }
            }
        }
    }
}

/// Simple collision detection system
fn collisionSystem(world: *zixel.World, dt: f32) !void {
    _ = dt;

    const transform_id = world.getComponentId(zixel.components.Transform) orelse return;
    const collider_id = world.getComponentId(zixel.components.Collider) orelse return;
    const tag_id = world.getComponentId(zixel.components.Tag) orelse return;

    // Get all entities with colliders
    var entities = std.ArrayList(zixel.Entity).init(world.allocator);
    defer entities.deinit();

    var query_iter = world.query(&[_]@TypeOf(transform_id){ transform_id, collider_id, tag_id }, &[_]@TypeOf(transform_id){});

    while (query_iter.next()) |entity| {
        try entities.append(entity);
    }

    // Simple collision detection between entities
    for (entities.items, 0..) |entity_a, i| {
        for (entities.items[i + 1 ..]) |entity_b| {
            if (checkCollision(world, entity_a, entity_b)) {
                handleCollision(world, entity_a, entity_b);
            }
        }
    }
}

fn checkCollision(world: *zixel.World, entity_a: zixel.Entity, entity_b: zixel.Entity) bool {
    const transform_a = world.getComponent(zixel.components.Transform, entity_a) orelse return false;
    const collider_a = world.getComponent(zixel.components.Collider, entity_a) orelse return false;
    const transform_b = world.getComponent(zixel.components.Transform, entity_b) orelse return false;
    const collider_b = world.getComponent(zixel.components.Collider, entity_b) orelse return false;

    // Simple distance calculation
    const dx = transform_a.position.x - transform_b.position.x;
    const dy = transform_a.position.y - transform_b.position.y;
    const distance = @sqrt(dx * dx + dy * dy);

    // Assume all colliders are circles with radius 20 for simplicity
    const radius_a: f32 = 20;
    const radius_b: f32 = 20;

    _ = collider_a;
    _ = collider_b;

    return distance < (radius_a + radius_b);
}

fn handleCollision(world: *zixel.World, entity_a: zixel.Entity, entity_b: zixel.Entity) void {
    const tag_a = world.getComponent(zixel.components.Tag, entity_a);
    const tag_b = world.getComponent(zixel.components.Tag, entity_b);

    if (tag_a) |tag_a_val| {
        if (tag_b) |tag_b_val| {
            // Player collecting collectibles
            if ((tag_a_val.has(.Player) and tag_b_val.has(.Collectible)) or
                (tag_a_val.has(.Collectible) and tag_b_val.has(.Player)))
            {
                const collectible_entity = if (tag_a_val.has(.Collectible)) entity_a else entity_b;

                // Mark collectible for destruction
                world.addComponent(collectible_entity, zixel.components.ToDestroy{}) catch {};

                std.debug.print("Player collected an item!\n", .{});
            }

            // Player touching enemy
            if ((tag_a_val.has(.Player) and tag_b_val.has(.Enemy)) or
                (tag_a_val.has(.Enemy) and tag_b_val.has(.Player)))
            {
                const player_entity = if (tag_a_val.has(.Player)) entity_a else entity_b;

                if (world.getComponent(zixel.components.Health, player_entity)) |health| {
                    health.damage(10.0);
                    health.invulnerability_timer = 1.0; // 1 second of invulnerability
                    health.is_invulnerable = true;

                    std.debug.print("Player took damage! Health: {d}\n", .{health.current});
                }
            }
        }
    }
}
