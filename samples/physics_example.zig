const std = @import("std");
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;

const Scene = zixel.Scene;
const World = zixel.World;
const Renderer = zixel.Renderer;
const Engine = zixel.Engine;
const Sprite = zixel.Sprite;
const Vec2 = zixel.Vec2;
const Color = zixel.Color;

pub const PhysicsScene = struct {
    alloc: Allocator,
    world: *World,
    renderer: *Renderer,
    sprites: std.ArrayList(Sprite),

    pub fn init(alloc: Allocator, world: *World, renderer: *Renderer) !PhysicsScene {
        var scene = PhysicsScene{
            .alloc = alloc,
            .world = world,
            .renderer = renderer,
            .sprites = .empty,
        };

        const wall_color = Color{ .r = 0.3, .g = 0.3, .b = 0.35, .a = 1 };

        // Ground
        const ground = try world.addStaticRect(400, 550, 700, 40, .{});
        try scene.sprites.append(alloc, Sprite.fromBody(ground, wall_color));

        // Left wall
        const left_wall = try world.addStaticRect(50, 350, 20, 400, .{});
        try scene.sprites.append(alloc, Sprite.fromBody(left_wall, wall_color));

        // Right wall
        const right_wall = try world.addStaticRect(750, 350, 20, 400, .{});
        try scene.sprites.append(alloc, Sprite.fromBody(right_wall, wall_color));

        // Falling boxes with different colors and sizes
        const box_colors = [_]Color{
            Color{ .r = 0.9, .g = 0.3, .b = 0.3, .a = 1 }, // Red
            Color{ .r = 0.3, .g = 0.9, .b = 0.3, .a = 1 }, // Green
            Color{ .r = 0.3, .g = 0.5, .b = 0.9, .a = 1 }, // Blue
            Color{ .r = 0.9, .g = 0.9, .b = 0.3, .a = 1 }, // Yellow
            Color{ .r = 0.9, .g = 0.5, .b = 0.2, .a = 1 }, // Orange
        };

        for (0..5) |i| {
            const fi: f32 = @floatFromInt(i);
            const size: f32 = 40 + fi * 5;

            const box = try world.addDynamicRect(
                200 + fi * 100, // x
                100 + fi * 30, // y
                size,
                size,
                .{ .mass = 1.0 + fi * 0.5, .restitution = 0.3, .friction = 0.5 },
            );
            try scene.sprites.append(alloc, Sprite.fromBody(box, box_colors[i]));
        }

        // UI element - not tied to physics (stays fixed on screen)
        try scene.sprites.append(alloc, Sprite.fromRect(10, 10, 150, 30, Color{ .r = 0, .g = 0, .b = 0, .a = 0.7 }));

        return scene;
    }

    pub fn update(self: *PhysicsScene, dt: f32) void {
        _ = self;
        _ = dt;
    }

    pub fn render(self: *PhysicsScene) void {
        for (self.sprites.items) |*sprite| {
            sprite.render(self.world, self.renderer);
        }
    }

    pub fn deinit(self: *PhysicsScene, alloc: Allocator) void {
        self.sprites.deinit(alloc);
        alloc.destroy(self);
    }
};

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
            .gravity = Vec2.init(0, 500),
        },
    });

    const scene_iface = try createScene(alloc, &engine.world, &engine.renderer);
    engine.setScene(scene_iface);

    engine.run();
}
