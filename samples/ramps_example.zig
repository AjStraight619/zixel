const std = @import("std");
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;

const Engine = zixel.Engine;
const Sprite = zixel.Sprite;
const Vec2 = zixel.Vec2;
const Color = zixel.Color;

pub const RampsScene = struct {
    pub const name = "ramps_example";
    pub const is_blocking = false;
    pub const is_opaque = false;

    ctx: Engine.Ctx,
    sprites: std.ArrayList(Sprite),

    pub fn init(ctx: Engine.Ctx) !RampsScene {
        var scene = RampsScene{
            .ctx = ctx,
            .sprites = .empty,
        };

        try scene.buildLevel();
        return scene;
    }

    fn buildLevel(self: *RampsScene) !void {
        const wall_color = Color{ .r = 0.25, .g = 0.25, .b = 0.3, .a = 1 };
        const ramp_color = Color{ .r = 0.4, .g = 0.35, .b = 0.5, .a = 1 };

        // Ground
        const ground = try self.ctx.world.addStaticRect(400, 580, 800, 40, .{});
        try self.sprites.append(self.ctx.alloc, Sprite.fromBody(ground, wall_color));

        // Left wall
        const left_wall = try self.ctx.world.addStaticRect(20, 300, 40, 600, .{});
        try self.sprites.append(self.ctx.alloc, Sprite.fromBody(left_wall, wall_color));

        // Right wall
        const right_wall = try self.ctx.world.addStaticRect(780, 300, 40, 600, .{});
        try self.sprites.append(self.ctx.alloc, Sprite.fromBody(right_wall, wall_color));

        // Ramp 1 (top-left, angled down-right)
        const ramp1 = try self.ctx.world.addStaticRect(200, 150, 250, 15, .{});
        if (self.ctx.world.getBody(ramp1)) |body| {
            body.rotation = 0.3;
        }
        try self.sprites.append(self.ctx.alloc, Sprite.fromBody(ramp1, ramp_color));

        // Ramp 2 (middle-right, angled down-left)
        const ramp2 = try self.ctx.world.addStaticRect(550, 280, 250, 15, .{});
        if (self.ctx.world.getBody(ramp2)) |body| {
            body.rotation = -0.25;
        }
        try self.sprites.append(self.ctx.alloc, Sprite.fromBody(ramp2, ramp_color));

        // Ramp 3 (bottom-left, angled down-right)
        const ramp3 = try self.ctx.world.addStaticRect(250, 420, 220, 15, .{});
        if (self.ctx.world.getBody(ramp3)) |body| {
            body.rotation = 0.35;
        }
        try self.sprites.append(self.ctx.alloc, Sprite.fromBody(ramp3, ramp_color));

        // Platform at bottom
        const platform = try self.ctx.world.addStaticRect(600, 500, 150, 15, .{});
        try self.sprites.append(self.ctx.alloc, Sprite.fromBody(platform, ramp_color));

        // Starter balls
        const ball_colors = [_]Color{
            Color{ .r = 1.0, .g = 0.4, .b = 0.3, .a = 1 },
            Color{ .r = 0.3, .g = 0.9, .b = 0.5, .a = 1 },
            Color{ .r = 0.4, .g = 0.6, .b = 1.0, .a = 1 },
            Color{ .r = 1.0, .g = 0.8, .b = 0.2, .a = 1 },
        };

        for (0..4) |i| {
            const fi: f32 = @floatFromInt(i);
            const ball = try self.ctx.world.addDynamicCircle(
                150 + fi * 30,
                30 + fi * 8,
                15,
                .{ .restitution = 0.5, .friction = 0.15 },
            );
            try self.sprites.append(self.ctx.alloc, Sprite.fromBody(ball, ball_colors[i]));
        }
    }

    pub fn update(self: *RampsScene, dt: f32) void {
        _ = dt;

        // Spawn circle at mouse position on click
        if (self.ctx.input.isMousePressed(.left)) {
            const pos = self.ctx.input.mousePosition();
            if (self.ctx.world.addDynamicCircle(pos.x, pos.y, 12, .{ .restitution = 0.6, .friction = 0.15 })) |handle| {
                const r = @mod(pos.x / 800.0 + 0.3, 1.0);
                const g = @mod(pos.y / 600.0 + 0.4, 1.0);
                const color = Color{ .r = r, .g = g, .b = 0.8, .a = 1 };
                self.sprites.append(self.ctx.alloc, Sprite.fromBody(handle, color)) catch {};
            } else |_| {}
        }

        // Spawn circle at top on spacebar
        if (self.ctx.input.isKeyPressed(.space)) {
            const x: f32 = 80 + @mod(@as(f32, @floatFromInt(self.ctx.world.step_count)), 100.0) * 1.5;
            if (self.ctx.world.addDynamicCircle(x, 30, 14, .{ .restitution = 0.55, .friction = 0.2 })) |handle| {
                const color = Color{ .r = 0.9, .g = 0.5, .b = 0.9, .a = 1 };
                self.sprites.append(self.ctx.alloc, Sprite.fromBody(handle, color)) catch {};
            } else |_| {}
        }

        // Spawn box on right-click
        if (self.ctx.input.isMousePressed(.right)) {
            const pos = self.ctx.input.mousePosition();
            if (self.ctx.world.addDynamicRect(pos.x, pos.y, 25, 25, .{ .restitution = 0.4, .friction = 0.4 })) |handle| {
                const color = Color{ .r = 0.6, .g = 0.4, .b = 0.3, .a = 1 };
                self.sprites.append(self.ctx.alloc, Sprite.fromBody(handle, color)) catch {};
            } else |_| {}
        }

        // Clear all on 'C'
        if (self.ctx.input.isKeyPressed(.c)) {
            self.ctx.world.clearBodies();
            self.sprites.clearRetainingCapacity();
            self.buildLevel() catch {};
        }
    }

    pub fn render(self: *RampsScene) void {
        for (self.sprites.items) |*sprite| {
            sprite.render(self.ctx.world, self.ctx.renderer);
        }
    }

    pub fn deinit(self: *RampsScene, alloc: Allocator) void {
        self.sprites.deinit(alloc);
        alloc.destroy(self);
    }
};

pub fn main() !void {
    var engine = try Engine.init(std.heap.page_allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Zixel Ramps - Click: circle, Right-click: box, Space: drop from top, C: clear",
        },
        .physics = .{
            .gravity = Vec2.init(0, 400),
            .debug_logging = true,
            .linear_damping = 0.002,
            .allow_sleeping = false,
        },
    });

    try engine.createScene(RampsScene);
    engine.run();
}
