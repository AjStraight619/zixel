const std = @import("std");
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;

const Scene = zixel.Scene;
const World = zixel.World;
const Renderer = zixel.Renderer;
const Input = zixel.Input;
const Engine = zixel.Engine;
const Sprite = zixel.Sprite;
const Vec2 = zixel.Vec2;
const Color = zixel.Color;
const Key = zixel.Key;
const MouseButton = zixel.MouseButton;

pub const PhysicsScene = struct {
    alloc: Allocator,
    world: *World,
    renderer: *Renderer,
    input: *Input,
    sprites: std.ArrayList(Sprite),

    pub fn init(alloc: Allocator, world: *World, renderer: *Renderer, input: *Input) !PhysicsScene {
        var scene = PhysicsScene{
            .alloc = alloc,
            .world = world,
            .renderer = renderer,
            .input = input,
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

        // A few starter boxes
        const box_colors = [_]Color{
            Color{ .r = 0.9, .g = 0.3, .b = 0.3, .a = 1 },
            Color{ .r = 0.3, .g = 0.9, .b = 0.3, .a = 1 },
            Color{ .r = 0.3, .g = 0.5, .b = 0.9, .a = 1 },
        };

        for (0..3) |i| {
            const fi: f32 = @floatFromInt(i);
            const box = try world.addDynamicRect(
                250 + fi * 150,
                50, // Higher drop for more bounce
                40,
                40,
                .{ .restitution = 0.6, .friction = 0.3 }, // More bouncy!
            );
            try scene.sprites.append(alloc, Sprite.fromBody(box, box_colors[i]));
        }

        // UI hint
        try scene.sprites.append(alloc, Sprite.fromRect(10, 10, 220, 25, Color{ .r = 0, .g = 0, .b = 0, .a = 0.7 }));

        return scene;
    }

    pub fn update(self: *PhysicsScene, dt: f32) void {
        _ = dt;

        // Spawn box at mouse position on click
        if (self.input.isMousePressed(.left)) {
            const pos = self.input.mousePosition();
            if (self.world.addDynamicRect(pos.x, pos.y, 30, 30, .{ .restitution = 0.7, .friction = 0.3 })) |handle| {
                const color = Color{ .r = 0.8, .g = 0.4, .b = 0.8, .a = 1 }; // Purple
                self.sprites.append(self.alloc, Sprite.fromBody(handle, color)) catch {};
            } else |_| {}
        }

        // Spawn box in center on spacebar
        if (self.input.isKeyPressed(.space)) {
            if (self.world.addDynamicRect(400, 50, 35, 35, .{ .restitution = 0.7, .friction = 0.3 })) |handle| {
                const color = Color{ .r = 0.4, .g = 0.8, .b = 0.8, .a = 1 }; // Cyan
                self.sprites.append(self.alloc, Sprite.fromBody(handle, color)) catch {};
            } else |_| {}
        }

        // Clear all dynamic bodies on 'C'
        if (self.input.isKeyPressed(.c)) {
            self.world.clearBodies();
            self.sprites.clearRetainingCapacity();
            // Re-add walls (they got cleared too)
            self.rebuildWalls() catch {};
        }
    }

    fn rebuildWalls(self: *PhysicsScene) !void {
        const wall_color = Color{ .r = 0.3, .g = 0.3, .b = 0.35, .a = 1 };
        const ground = try self.world.addStaticRect(400, 550, 700, 40, .{});
        try self.sprites.append(self.alloc, Sprite.fromBody(ground, wall_color));
        const left_wall = try self.world.addStaticRect(50, 350, 20, 400, .{});
        try self.sprites.append(self.alloc, Sprite.fromBody(left_wall, wall_color));
        const right_wall = try self.world.addStaticRect(750, 350, 20, 400, .{});
        try self.sprites.append(self.alloc, Sprite.fromBody(right_wall, wall_color));
        // UI hint
        try self.sprites.append(self.alloc, Sprite.fromRect(10, 10, 220, 25, Color{ .r = 0, .g = 0, .b = 0, .a = 0.7 }));
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

pub fn createScene(alloc: Allocator, world: *World, renderer: *Renderer, input: *Input) !Scene {
    const ptr = try alloc.create(PhysicsScene);
    ptr.* = try PhysicsScene.init(alloc, world, renderer, input);
    return Scene.init(ptr);
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    var engine = try Engine.init(alloc, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Zixel Physics - Click to spawn, Space for center, C to clear",
        },
        .physics = .{
            .gravity = Vec2.init(0, 500),
            .debug_logging = true, // Log physics stats every second
        },
    });

    const scene_iface = try createScene(alloc, &engine.world, &engine.renderer, &engine.input);
    engine.setScene(scene_iface);

    engine.run();
}
