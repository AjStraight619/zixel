const std = @import("std");
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;

const Engine = zixel.Engine;
const Vec2 = zixel.Vec2;
const Color = zixel.Color;
const Entity = zixel.Entity;
const EntityDef = zixel.EntityDef;
const BodyKind = zixel.BodyKind;
const PhysicsShape = zixel.PhysicsShape;

pub const AngularRectsScene = struct {
    pub const name = "angular_vel_example";
    pub const is_blocking = false;
    pub const is_opaque = false;

    ctx: Engine.Ctx,

    pub fn init(ctx: Engine.Ctx) !AngularRectsScene {
        var self = AngularRectsScene{ .ctx = ctx };
        try self.buildLevel();
        return self;
    }

    fn buildLevel(self: *AngularRectsScene) !void {
        const wall_color = Color{ .r = 0.22, .g = 0.22, .b = 0.26, .a = 1 };
        const striker_color = Color{ .r = 0.9, .g = 0.35, .b = 0.3, .a = 1 };
        const target_color = Color{ .r = 0.35, .g = 0.75, .b = 0.95, .a = 1 };
        const extra_color = Color{ .r = 0.8, .g = 0.7, .b = 0.3, .a = 1 };

        // Ground
        _ = try self.ctx.world.spawn(.{
            .name = "ground",
            .owner = .{ .scene = name },
            .position = Vec2.init(400, 585),
            .body = .{ .kind = .static, .shape = PhysicsShape.rect(800, 30) },
            .sprite = .{ .color = wall_color },
        });

        // Left wall
        _ = try self.ctx.world.spawn(.{
            .owner = .{ .scene = name },
            .position = Vec2.init(15, 300),
            .body = .{ .kind = .static, .shape = PhysicsShape.rect(30, 600) },
            .sprite = .{ .color = wall_color },
        });

        // Right wall
        _ = try self.ctx.world.spawn(.{
            .owner = .{ .scene = name },
            .position = Vec2.init(785, 300),
            .body = .{ .kind = .static, .shape = PhysicsShape.rect(30, 600) },
            .sprite = .{ .color = wall_color },
        });

        // Target
        _ = try self.ctx.world.*.spawn(.{
            .name = "target",
            .owner = .{ .scene = name },
            .position = Vec2.init(520, 480),
            .body = .{
                .kind = .dynamic,
                .shape = PhysicsShape.rect(80, 40),
                .restitution = 0.25,
                .friction = 0.35,
                .mass = 2.0,
            },
            .sprite = .{ .color = target_color },
        });

        // Striker
        _ = try self.ctx.world.*.spawn(.{
            .name = "striker",
            .owner = .{ .scene = name },
            .position = Vec2.init(180, 465),
            .body = .{
                .kind = .dynamic,
                .shape = PhysicsShape.rect(90, 30),
                .restitution = 0.25,
                .friction = 0.35,
                .velocity = Vec2.init(380, 0),
                .mass = 2.0,
            },
            .sprite = .{ .color = striker_color },
        });

        // Corner target
        _ = try self.ctx.world.*.spawn(.{
            .owner = .{ .scene = name },
            .position = Vec2.init(260, 510),
            .body = .{
                .kind = .dynamic,
                .shape = PhysicsShape.rect(70, 50),
                .restitution = 0.2,
                .friction = 0.45,
                .mass = 2.0,
            },
            .sprite = .{ .color = extra_color },
        });

        // Dropper (rotated)
        const dropper = try self.ctx.world.spawn(.{
            .owner = .{ .scene = name },
            .position = Vec2.init(220, 220),
            .rotation = 0.25,
            .body = .{
                .kind = .dynamic,
                .shape = PhysicsShape.rect(45, 45),
                .restitution = 0.2,
                .friction = 0.4,
                .mass = 1.0,
            },
            .sprite = .{ .color = Color{ .r = 0.7, .g = 0.45, .b = 0.9, .a = 1 } },
        });
        _ = dropper;
    }

    pub fn update(self: *AngularRectsScene, dt: f32) void {
        _ = dt;

        // Click: spawn a box with sideways velocity
        if (self.ctx.input.isMousePressed(.left)) {
            const p = self.ctx.input.mousePosition();
            _ = self.ctx.world.spawn(.{
                .owner = .{ .scene = name },
                .position = p,
                .body = .{
                    .kind = .dynamic,
                    .shape = PhysicsShape.rect(40, 25),
                    .restitution = 0.25,
                    .friction = 0.45,
                    .velocity = Vec2.init(240, 0),
                    .mass = 1.5,
                },
                .sprite = .{ .color = Color{ .r = 0.9, .g = 0.55, .b = 0.25, .a = 1 } },
            }) catch {};
        }

        // Space: reset the main striker/target positions
        if (self.ctx.input.isKeyPressed(.space)) {
            if (self.ctx.world.*.getByName("striker")) |e| {
                e.body.position = Vec2.init(180, 465);
                e.body.rotation = 0.0;
                e.body.velocity = Vec2.init(380, 0);
                e.body.angular_velocity = 0.0;
                e.body.is_sleeping = false;
                e.body.sleep_time = 0.0;
            }
            if (self.ctx.world.*.getByName("target")) |e| {
                e.body.position = Vec2.init(520, 480);
                e.body.rotation = 0.0;
                e.body.velocity = Vec2.zero;
                e.body.angular_velocity = 0.0;
                e.body.is_sleeping = false;
                e.body.sleep_time = 0.0;
            }
        }

        // C: full reset
        if (self.ctx.input.isKeyPressed(.c)) {
            self.ctx.world.*.removeByOwner(.{ .scene = name });
            self.buildLevel() catch {};
        }
    }

    pub fn render(self: *AngularRectsScene) void {
        self.ctx.world.*.renderAll(self.ctx.renderer);
    }

    pub fn deinit(self: *AngularRectsScene, alloc: Allocator) void {
        self.ctx.world.*.removeByOwner(.{ .scene = name });
        alloc.destroy(self);
    }
};

pub fn main() !void {
    var engine = try Engine.init(std.heap.page_allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Angular Rects - Space: reset striker, Click: spawn moving box, C: reset all",
        },
        .physics = .{
            .gravity = Vec2.init(0, 450),
            .debug_logging = true,
            .linear_damping = 0.001,
            .allow_sleeping = false,
        },
    });

    try engine.createScene(AngularRectsScene);
    engine.run();
}
