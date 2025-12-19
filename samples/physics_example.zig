const std = @import("std");
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;

const Engine = zixel.Engine;
const Sprite = zixel.Sprite;
const Vec2 = zixel.Vec2;
const Color = zixel.Color;

pub const PhysicsScene = struct {
    pub const name = "physics_example";

    ctx: Engine.Ctx,
    sprites: std.ArrayList(Sprite),

    pub fn init(ctx: Engine.Ctx) !PhysicsScene {
        var scene = PhysicsScene{
            .ctx = ctx,
            .sprites = .empty,
        };

        const wall_color = Color{ .r = 0.3, .g = 0.3, .b = 0.35, .a = 1 };

        // Ground
        const ground = try ctx.world.addStaticRect(400, 550, 700, 40, .{});
        try scene.sprites.append(ctx.alloc, Sprite.fromBody(ground, wall_color));

        // Left wall
        const left_wall = try ctx.world.addStaticRect(50, 350, 20, 400, .{});
        try scene.sprites.append(ctx.alloc, Sprite.fromBody(left_wall, wall_color));

        // Right wall
        const right_wall = try ctx.world.addStaticRect(750, 350, 20, 400, .{});
        try scene.sprites.append(ctx.alloc, Sprite.fromBody(right_wall, wall_color));

        // A few starter boxes
        const box_colors = [_]Color{
            Color{ .r = 0.9, .g = 0.3, .b = 0.3, .a = 1 },
            Color{ .r = 0.3, .g = 0.9, .b = 0.3, .a = 1 },
            Color{ .r = 0.3, .g = 0.5, .b = 0.9, .a = 1 },
        };

        for (0..3) |i| {
            const fi: f32 = @floatFromInt(i);
            const box = try ctx.world.addDynamicRect(
                250 + fi * 150,
                50,
                40,
                40,
                .{ .restitution = 0.6, .friction = 0.3 },
            );
            try scene.sprites.append(ctx.alloc, Sprite.fromBody(box, box_colors[i]));
        }

        // UI hint
        try scene.sprites.append(ctx.alloc, Sprite.fromRect(10, 10, 220, 25, Color{ .r = 0, .g = 0, .b = 0, .a = 0.7 }));

        return scene;
    }

    pub fn update(self: *PhysicsScene, dt: f32) void {
        _ = dt;

        // Spawn box at mouse position on click
        if (self.ctx.input.isMousePressed(.left)) {
            const pos = self.ctx.input.mousePosition();
            if (self.ctx.world.addDynamicRect(pos.x, pos.y, 30, 30, .{ .restitution = 0.7, .friction = 0.3 })) |handle| {
                const color = Color{ .r = 0.8, .g = 0.4, .b = 0.8, .a = 1 };
                self.sprites.append(self.ctx.alloc, Sprite.fromBody(handle, color)) catch {};
            } else |_| {}
        }

        // Spawn box in center on spacebar
        if (self.ctx.input.isKeyPressed(.space)) {
            if (self.ctx.world.addDynamicRect(400, 50, 35, 35, .{ .restitution = 0.7, .friction = 0.3 })) |handle| {
                const color = Color{ .r = 0.4, .g = 0.8, .b = 0.8, .a = 1 };
                self.sprites.append(self.ctx.alloc, Sprite.fromBody(handle, color)) catch {};
            } else |_| {}
        }

        // Clear all dynamic bodies on 'C'
        if (self.ctx.input.isKeyPressed(.c)) {
            self.ctx.world.clearBodies();
            self.sprites.clearRetainingCapacity();
            self.rebuildWalls() catch {};
        }
    }

    fn rebuildWalls(self: *PhysicsScene) !void {
        const wall_color = Color{ .r = 0.3, .g = 0.3, .b = 0.35, .a = 1 };
        const ground = try self.ctx.world.addStaticRect(400, 550, 700, 40, .{});
        try self.sprites.append(self.ctx.alloc, Sprite.fromBody(ground, wall_color));
        const left_wall = try self.ctx.world.addStaticRect(50, 350, 20, 400, .{});
        try self.sprites.append(self.ctx.alloc, Sprite.fromBody(left_wall, wall_color));
        const right_wall = try self.ctx.world.addStaticRect(750, 350, 20, 400, .{});
        try self.sprites.append(self.ctx.alloc, Sprite.fromBody(right_wall, wall_color));
        try self.sprites.append(self.ctx.alloc, Sprite.fromRect(10, 10, 220, 25, Color{ .r = 0, .g = 0, .b = 0, .a = 0.7 }));
    }

    pub fn render(self: *PhysicsScene) void {
        for (self.sprites.items) |*sprite| {
            sprite.render(self.ctx.world, self.ctx.renderer);
        }
    }

    pub fn deinit(self: *PhysicsScene, alloc: Allocator) void {
        self.sprites.deinit(alloc);
        alloc.destroy(self);
    }
};

pub fn main() !void {
    var engine = try Engine.init(std.heap.page_allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Zixel Physics - Click to spawn, Space for center, C to clear",
        },
        .physics = .{
            .gravity = Vec2.init(0, 500),
            .debug_logging = true,
        },
    });

    try engine.createScene(PhysicsScene);
    engine.run();
}
