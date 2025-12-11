const std = @import("std");
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;

const Scene = zixel.Scene;
const World = zixel.World;
const Renderer = zixel.Renderer;
const Engine = zixel.Engine;
const Body = zixel.Body;
const BodyHandle = zixel.BodyHandle;
const PhysicsShape = zixel.PhysicsShape;
const Vec2 = zixel.Vec2;
const Color = zixel.Color;

/// A simple sprite that tracks a physics body via its handle.
/// No texture - just a colored shape.
const PhysicsSprite = struct {
    handle: BodyHandle,
    width: f32,
    height: f32,
    color: Color,
};

pub const PhysicsScene = struct {
    alloc: Allocator,
    world: *World,
    renderer: *Renderer,
    sprites: std.ArrayList(PhysicsSprite),

    pub fn init(alloc: Allocator, world: *World, renderer: *Renderer) !PhysicsScene {
        var scene = PhysicsScene{
            .alloc = alloc,
            .world = world,
            .renderer = renderer,
            .sprites = .empty,
        };

        // Create ground (static body at bottom of screen)
        const ground_width: f32 = 700;
        const ground_height: f32 = 40;
        const ground_shape = PhysicsShape.initRectangle(ground_width, ground_height);
        const ground_body = Body.initStatic(
            ground_shape,
            Vec2.init(400, 550), // center position
            .{},
        );
        const ground_handle = try world.addBody(ground_body);
        try scene.sprites.append(alloc, .{
            .handle = ground_handle,
            .width = ground_width,
            .height = ground_height,
            .color = Color{ .r = 0.3, .g = 0.3, .b = 0.35, .a = 1 },
        });

        // Create some falling boxes at different positions
        const box_colors = [_]Color{
            Color{ .r = 0.9, .g = 0.3, .b = 0.3, .a = 1 }, // Red
            Color{ .r = 0.3, .g = 0.9, .b = 0.3, .a = 1 }, // Green
            Color{ .r = 0.3, .g = 0.5, .b = 0.9, .a = 1 }, // Blue
            Color{ .r = 0.9, .g = 0.9, .b = 0.3, .a = 1 }, // Yellow
            Color{ .r = 0.9, .g = 0.5, .b = 0.2, .a = 1 }, // Orange
        };

        for (0..5) |i| {
            const fi: f32 = @floatFromInt(i);
            const box_size: f32 = 40 + fi * 5; // Slightly different sizes
            const box_shape = PhysicsShape.initRectangle(box_size, box_size);

            const box_body = Body.initDynamic(
                box_shape,
                Vec2.init(200 + fi * 100, 100 + fi * 30), // Staggered positions
                .{
                    .mass = 1.0 + fi * 0.5, // Different masses
                    .restitution = 0.3,
                    .friction = 0.5,
                },
            );

            const box_handle = try world.addBody(box_body);
            try scene.sprites.append(
                alloc,
                .{
                    .handle = box_handle,
                    .width = box_size,
                    .height = box_size,
                    .color = box_colors[i],
                },
            );
        }

        // Add some walls on the sides
        const wall_height: f32 = 400;
        const wall_width: f32 = 20;

        // Left wall
        const left_wall = Body.initStatic(
            PhysicsShape.initRectangle(wall_width, wall_height),
            Vec2.init(50, 350),
            .{},
        );
        const left_handle = try world.addBody(left_wall);
        try scene.sprites.append(alloc, .{
            .handle = left_handle,
            .width = wall_width,
            .height = wall_height,
            .color = Color{ .r = 0.3, .g = 0.3, .b = 0.35, .a = 1 },
        });

        // Right wall
        const right_wall = Body.initStatic(
            PhysicsShape.initRectangle(wall_width, wall_height),
            Vec2.init(750, 350),
            .{},
        );
        const right_handle = try world.addBody(right_wall);
        try scene.sprites.append(alloc, .{
            .handle = right_handle,
            .width = wall_width,
            .height = wall_height,
            .color = Color{ .r = 0.3, .g = 0.3, .b = 0.35, .a = 1 },
        });

        return scene;
    }

    /// Called every frame by the Engine
    pub fn update(self: *PhysicsScene, dt: f32) void {
        // Physics is updated by the engine automatically
        _ = self;
        _ = dt;
    }

    /// Called every frame by the Engine between beginFrame/endFrame
    pub fn render(self: *PhysicsScene) void {
        const r = self.renderer;

        // Draw all sprites based on their physics body positions
        for (self.sprites.items) |sprite| {
            // Get the body from the handle - this is O(1) and checks for stale handles
            if (self.world.getBody(sprite.handle)) |body| {
                // Body position is center, so offset to top-left for drawing
                const draw_x = body.position.x - sprite.width / 2;
                const draw_y = body.position.y - sprite.height / 2;

                r.drawRect(draw_x, draw_y, sprite.width, sprite.height, sprite.color);

                // Draw outline to show rotation would be nice, but for now just solid
            }
        }

        // Draw some UI text info
        r.drawRect(10, 10, 200, 30, Color{ .r = 0, .g = 0, .b = 0, .a = 0.5 });
    }

    /// Called when the Engine switches scenes or shuts down
    pub fn deinit(self: *PhysicsScene, alloc: Allocator) void {
        self.sprites.deinit(alloc);
        alloc.destroy(self);
    }
};

/// Helper: allocate PhysicsScene and wrap it in the vtable-based Scene type.
pub fn createScene(alloc: Allocator, world: *World, renderer: *Renderer) !Scene {
    const ptr = try alloc.create(PhysicsScene);
    ptr.* = try PhysicsScene.init(alloc, world, renderer);
    return Scene.init(ptr);
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    var engine = try Engine.init(alloc, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Zixel Physics Example",
        },
        .physics = .{
            .gravity = Vec2.init(0, 500), // Reasonable gravity
        },
    });

    const scene_iface = try createScene(alloc, &engine.world, &engine.renderer);
    engine.setScene(scene_iface);

    engine.run();
}
