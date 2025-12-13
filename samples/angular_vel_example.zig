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

pub const AngularRectsScene = struct {
    alloc: Allocator,
    world: *World,
    renderer: *Renderer,
    input: *Input,
    sprites: std.ArrayList(Sprite),

    striker: ?zixel.BodyHandle = null,
    target: ?zixel.BodyHandle = null,

    pub fn init(alloc: Allocator, world: *World, renderer: *Renderer, input: *Input) !AngularRectsScene {
        var scene = AngularRectsScene{
            .alloc = alloc,
            .world = world,
            .renderer = renderer,
            .input = input,
            .sprites = .empty,
        };

        try scene.buildLevel();
        return scene;
    }

    fn buildLevel(self: *AngularRectsScene) !void {
        const wall_color = Color{ .r = 0.22, .g = 0.22, .b = 0.26, .a = 1 };
        const striker_color = Color{ .r = 0.9, .g = 0.35, .b = 0.3, .a = 1 };
        const target_color = Color{ .r = 0.35, .g = 0.75, .b = 0.95, .a = 1 };
        const extra_color = Color{ .r = 0.8, .g = 0.7, .b = 0.3, .a = 1 };

        // Bounds
        const ground = try self.world.addStaticRect(400, 585, 800, 30, .{});
        try self.sprites.append(self.alloc, Sprite.fromBody(ground, wall_color));

        const left_wall = try self.world.addStaticRect(15, 300, 30, 600, .{});
        try self.sprites.append(self.alloc, Sprite.fromBody(left_wall, wall_color));

        const right_wall = try self.world.addStaticRect(785, 300, 30, 600, .{});
        try self.sprites.append(self.alloc, Sprite.fromBody(right_wall, wall_color));

        // --------------------------------------------------------------------
        // Setup A: horizontal "striker" hits target slightly off-center.
        // This should produce clear angular velocity on both boxes.
        // --------------------------------------------------------------------

        // Target sits still near the middle.
        const target = try self.world.addDynamicRect(
            520,
            480,
            80,
            40,
            .{
                .restitution = 0.25,
                .friction = 0.35,
                .mass = 2.0,
                .inertia = 1.0,
            },
        );
        self.target = target;
        try self.sprites.append(self.alloc, Sprite.fromBody(target, target_color));

        // Striker starts left and moves right.
        // Place it slightly above the target center so it clips the upper edge.
        const striker = try self.world.addDynamicRect(
            180,
            465,
            90,
            30,
            .{
                .restitution = 0.25,
                .friction = 0.35,
                .velocity = Vec2.init(380, 0),
                .mass = 2.0,
                .inertia = 1.0,
            },
        );
        self.striker = striker;
        try self.sprites.append(self.alloc, Sprite.fromBody(striker, striker_color));

        // --------------------------------------------------------------------
        // Setup B: falling box clips the corner of another box
        // (makes spin obvious even if Setup A ends up mostly head-on).
        // --------------------------------------------------------------------

        const corner_target = try self.world.addDynamicRect(
            260,
            510,
            70,
            50,
            .{
                .restitution = 0.2,
                .friction = 0.45,
                .mass = 2.0,
                .inertia = 1.0,
            },
        );
        try self.sprites.append(self.alloc, Sprite.fromBody(corner_target, extra_color));

        const dropper = try self.world.addDynamicRect(
            220,
            220,
            45,
            45,
            .{
                .restitution = 0.2,
                .friction = 0.4,
                .mass = 1.0,
                .inertia = 1.0,
            },
        );
        if (self.world.getBody(dropper)) |b| {
            // Slight tilt so it doesn’t look too “perfect”.
            b.rotation = 0.25;
        }
        try self.sprites.append(self.alloc, Sprite.fromBody(dropper, Color{ .r = 0.7, .g = 0.45, .b = 0.9, .a = 1 }));
    }

    pub fn update(self: *AngularRectsScene, dt: f32) void {
        _ = dt;

        // Click: spawn a box with sideways velocity to create more edge hits.
        if (self.input.isMousePressed(.left)) {
            const p = self.input.mousePosition();
            if (self.world.addDynamicRect(
                p.x,
                p.y,
                40,
                25,
                .{
                    .restitution = 0.25,
                    .friction = 0.45,
                    .velocity = Vec2.init(240, 0),
                    .mass = 1.5,
                    .inertia = 1.0,
                },
            )) |h| {
                const c = Color{ .r = 0.9, .g = 0.55, .b = 0.25, .a = 1 };
                self.sprites.append(self.alloc, Sprite.fromBody(h, c)) catch {};
            } else |_| {}
        }

        // Space: reset the main striker/target positions for repeatable testing.
        if (self.input.isKeyPressed(.space)) {
            if (self.striker) |hs| {
                if (self.world.getBody(hs)) |b| {
                    b.position = Vec2.init(180, 465);
                    b.rotation = 0.0;
                    b.velocity = Vec2.init(380, 0);
                    b.angular_velocity = 0.0;
                    b.is_sleeping = false;
                    b.sleep_time = 0.0;
                }
            }
            if (self.target) |ht| {
                if (self.world.getBody(ht)) |b| {
                    b.position = Vec2.init(520, 480);
                    b.rotation = 0.0;
                    b.velocity = Vec2.zero;
                    b.angular_velocity = 0.0;
                    b.is_sleeping = false;
                    b.sleep_time = 0.0;
                }
            }
        }

        // C: full reset
        if (self.input.isKeyPressed(.c)) {
            self.world.clearBodies();
            self.sprites.clearRetainingCapacity();
            self.striker = null;
            self.target = null;
            self.buildLevel() catch {};
        }
    }

    pub fn render(self: *AngularRectsScene) void {
        for (self.sprites.items) |*sprite| {
            sprite.render(self.world, self.renderer);
        }
    }

    pub fn deinit(self: *AngularRectsScene, alloc: Allocator) void {
        self.sprites.deinit(alloc);
        alloc.destroy(self);
    }
};

pub fn createScene(alloc: Allocator, world: *World, renderer: *Renderer, input: *Input) !Scene {
    const ptr = try alloc.create(AngularRectsScene);
    ptr.* = try AngularRectsScene.init(alloc, world, renderer, input);
    return Scene.init(ptr);
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    var engine = try Engine.init(alloc, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Angular Rects - Space: reset striker, Click: spawn moving box, C: reset all",
        },
        .physics = .{
            .gravity = Vec2.init(0, 450),
            .debug_logging = true,
            .linear_damping = 0.001, // keep it low so spin stays visible
            .allow_sleeping = false,
        },
    });

    const scene_iface = try createScene(alloc, &engine.world, &engine.renderer, &engine.input);
    engine.setScene(scene_iface);

    engine.run();
}
