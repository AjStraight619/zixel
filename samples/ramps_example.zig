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

pub const RampsScene = struct {
    alloc: Allocator,
    world: *World,
    renderer: *Renderer,
    input: *Input,
    sprites: std.ArrayList(Sprite),

    pub fn init(alloc: Allocator, world: *World, renderer: *Renderer, input: *Input) !RampsScene {
        var scene = RampsScene{
            .alloc = alloc,
            .world = world,
            .renderer = renderer,
            .input = input,
            .sprites = .empty,
        };

        try scene.buildLevel();

        return scene;
    }

    fn buildLevel(self: *RampsScene) !void {
        const wall_color = Color{ .r = 0.25, .g = 0.25, .b = 0.3, .a = 1 };
        const ramp_color = Color{ .r = 0.4, .g = 0.35, .b = 0.5, .a = 1 };

        // Ground
        const ground = try self.world.addStaticRect(400, 580, 800, 40, .{});
        try self.sprites.append(self.alloc, Sprite.fromBody(ground, wall_color));

        // Left wall
        const left_wall = try self.world.addStaticRect(20, 300, 40, 600, .{});
        try self.sprites.append(self.alloc, Sprite.fromBody(left_wall, wall_color));

        // Right wall
        const right_wall = try self.world.addStaticRect(780, 300, 40, 600, .{});
        try self.sprites.append(self.alloc, Sprite.fromBody(right_wall, wall_color));

        // Ramp 1 (top-left, angled down-right) - using wide thin rect
        const ramp1 = try self.world.addStaticRect(200, 150, 250, 15, .{});
        if (self.world.getBody(ramp1)) |body| {
            body.rotation = 0.3; // ~17 degrees
        }
        try self.sprites.append(self.alloc, Sprite.fromBody(ramp1, ramp_color));

        // Ramp 2 (middle-right, angled down-left)
        const ramp2 = try self.world.addStaticRect(550, 280, 250, 15, .{});
        if (self.world.getBody(ramp2)) |body| {
            body.rotation = -0.25;
        }
        try self.sprites.append(self.alloc, Sprite.fromBody(ramp2, ramp_color));

        // Ramp 3 (bottom-left, angled down-right)
        const ramp3 = try self.world.addStaticRect(250, 420, 220, 15, .{});
        if (self.world.getBody(ramp3)) |body| {
            body.rotation = 0.35;
        }
        try self.sprites.append(self.alloc, Sprite.fromBody(ramp3, ramp_color));

        // Platform at bottom (catch balls)
        const platform = try self.world.addStaticRect(600, 500, 150, 15, .{});
        try self.sprites.append(self.alloc, Sprite.fromBody(platform, ramp_color));

        // Some starter balls - spawn over the center of ramp1 (at x=200)
        const ball_colors = [_]Color{
            Color{ .r = 1.0, .g = 0.4, .b = 0.3, .a = 1 }, // Red-orange
            Color{ .r = 0.3, .g = 0.9, .b = 0.5, .a = 1 }, // Green
            Color{ .r = 0.4, .g = 0.6, .b = 1.0, .a = 1 }, // Blue
            Color{ .r = 1.0, .g = 0.8, .b = 0.2, .a = 1 }, // Yellow
        };

        for (0..4) |i| {
            const fi: f32 = @floatFromInt(i);
            const ball = try self.world.addDynamicCircle(
                150 + fi * 30, // Stagger horizontally, centered over ramp
                30 + fi * 8, // Stagger vertically
                15, // radius
                .{ .restitution = 0.5, .friction = 0.15 }, // Slightly less friction
            );
            try self.sprites.append(self.alloc, Sprite.fromBody(ball, ball_colors[i]));
        }
    }

    pub fn update(self: *RampsScene, dt: f32) void {
        _ = dt;

        // Spawn circle at mouse position on click
        if (self.input.isMousePressed(.left)) {
            const pos = self.input.mousePosition();
            if (self.world.addDynamicCircle(pos.x, pos.y, 12, .{ .restitution = 0.6, .friction = 0.15 })) |handle| {
                // Random-ish color based on position
                const r = @mod(pos.x / 800.0 + 0.3, 1.0);
                const g = @mod(pos.y / 600.0 + 0.4, 1.0);
                const color = Color{ .r = r, .g = g, .b = 0.8, .a = 1 };
                self.sprites.append(self.alloc, Sprite.fromBody(handle, color)) catch {};
            } else |_| {}
        }

        // Spawn circle at top on spacebar
        if (self.input.isKeyPressed(.space)) {
            // Random-ish x position based on frame count
            const x: f32 = 80 + @mod(@as(f32, @floatFromInt(self.world.step_count)), 100.0) * 1.5;
            if (self.world.addDynamicCircle(x, 30, 14, .{ .restitution = 0.55, .friction = 0.2 })) |handle| {
                const color = Color{ .r = 0.9, .g = 0.5, .b = 0.9, .a = 1 }; // Pink
                self.sprites.append(self.alloc, Sprite.fromBody(handle, color)) catch {};
            } else |_| {}
        }

        // Spawn box on right-click (mix shapes)
        if (self.input.isMousePressed(.right)) {
            const pos = self.input.mousePosition();
            if (self.world.addDynamicRect(pos.x, pos.y, 25, 25, .{ .restitution = 0.4, .friction = 0.4 })) |handle| {
                const color = Color{ .r = 0.6, .g = 0.4, .b = 0.3, .a = 1 }; // Brown
                self.sprites.append(self.alloc, Sprite.fromBody(handle, color)) catch {};
            } else |_| {}
        }

        // Clear all on 'C'
        if (self.input.isKeyPressed(.c)) {
            self.world.clearBodies();
            self.sprites.clearRetainingCapacity();
            self.buildLevel() catch {};
        }
    }

    pub fn render(self: *RampsScene) void {
        for (self.sprites.items) |*sprite| {
            sprite.render(self.world, self.renderer);
        }
    }

    pub fn deinit(self: *RampsScene, alloc: Allocator) void {
        self.sprites.deinit(alloc);
        alloc.destroy(self);
    }
};

pub fn createScene(alloc: Allocator, world: *World, renderer: *Renderer, input: *Input) !Scene {
    const ptr = try alloc.create(RampsScene);
    ptr.* = try RampsScene.init(alloc, world, renderer, input);
    return Scene.init(ptr);
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    var engine = try Engine.init(alloc, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Zixel Ramps - Click: circle, Right-click: box, Space: drop from top, C: clear",
        },
        .physics = .{
            .gravity = Vec2.init(0, 400), // Slightly lighter gravity for rolling
            .debug_logging = true,
            .linear_damping = 0.02,
            .allow_sleeping = false,
        },
    });

    const scene_iface = try createScene(alloc, &engine.world, &engine.renderer, &engine.input);
    engine.setScene(scene_iface);

    engine.run();
}
