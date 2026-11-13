//! Physics lab: small scenes for looking at how the solver behaves.
//!
//!   zig build run-physics-lab                  window; keys 1-7 pick a scene
//!   zig build run-physics-lab -- --headless    runs every scene and prints measurements
//!
//! In the window: R resets the scene, left click drops a ball, right click
//! drops a box. Bodies are drawn darker while they are asleep, and every ball
//! has a spoke so rolling is visible.
const std = @import("std");
const zixel = @import("zixel_new");
const sapp = @import("sokol").app;
const Allocator = std.mem.Allocator;

const Engine = zixel.Engine;
const Vec2 = zixel.Vec2;
const Color = zixel.Color;
const EntityHandle = zixel.EntityHandle;
const BodyKind = zixel.BodyKind;

const width = 900;
const height = 650;
const floor_y = 570;
const default_gravity = Vec2.init(0, 980);
const step_dt: f32 = 1.0 / 60.0;

const wall_color = Color{ .r = 0.24, .g = 0.25, .b = 0.29, .a = 1 };
const prop_color = Color{ .r = 0.42, .g = 0.44, .b = 0.5, .a = 1 };
const palette = [_]Color{
    .{ .r = 0.93, .g = 0.42, .b = 0.35, .a = 1 },
    .{ .r = 0.36, .g = 0.72, .b = 0.95, .a = 1 },
    .{ .r = 0.45, .g = 0.85, .b = 0.5, .a = 1 },
    .{ .r = 0.98, .g = 0.8, .b = 0.3, .a = 1 },
    .{ .r = 0.75, .g = 0.55, .b = 0.95, .a = 1 },
};

const Options = struct {
    kind: BodyKind = .dynamic,
    rotation: f32 = 0,
    friction: f32 = 0.5,
    restitution: f32 = 0.2,
    velocity: Vec2 = Vec2.zero,
    color: Color = palette[0],
};

/// A body whose movement the headless run reports.
const Probe = struct {
    handle: EntityHandle,
    label: []const u8,
    start: Vec2,
};

const Scenario = struct {
    name: []const u8,
    /// How long the headless run simulates this scene.
    seconds: f32,
    build: *const fn (lab: *Lab) anyerror!void,
};

const scenarios = [_]Scenario{
    .{ .name = "Round on round", .seconds = 30, .build = Lab.buildRoundOnRound },
    .{ .name = "Box stacks", .seconds = 10, .build = Lab.buildBoxStacks },
    .{ .name = "Box pyramid", .seconds = 10, .build = Lab.buildPyramid },
    .{ .name = "Ramp and friction", .seconds = 6, .build = Lab.buildRamp },
    .{ .name = "Restitution", .seconds = 6, .build = Lab.buildRestitution },
    .{ .name = "Fast bodies and thin walls", .seconds = 2, .build = Lab.buildTunnelling },
    .{ .name = "Pile", .seconds = 10, .build = Lab.buildPile },
};

fn title(comptime index: usize) [:0]const u8 {
    return std.fmt.comptimePrint("Physics lab {d}/{d}: {s}    [1-{d}] scene  [R] reset  [click] spawn", .{
        index + 1, scenarios.len, scenarios[index].name, scenarios.len,
    });
}

const titles = blk: {
    var all: [scenarios.len][:0]const u8 = undefined;
    for (&all, 0..) |*t, i| t.* = title(i);
    break :blk all;
};

const Lab = struct {
    pub const name = "physics_lab";
    pub const is_blocking = false;
    pub const is_opaque = false;

    ctx: Engine.Ctx,
    current: usize = 0,
    probes: std.ArrayList(Probe) = .empty,
    spawned: u32 = 0,

    pub fn init(ctx: Engine.Ctx) !Lab {
        var self = Lab{ .ctx = ctx };
        try self.load(0);
        return self;
    }

    pub fn deinit(self: *Lab, alloc: Allocator) void {
        self.probes.deinit(alloc);
    }

    pub fn load(self: *Lab, index: usize) !void {
        self.ctx.world.clear();
        self.probes.clearRetainingCapacity();
        self.current = index;
        self.ctx.physics.cfg.gravity = default_gravity;

        // Thick walls outside the view, so nothing can leave by going fast.
        _ = try self.box(width / 2, floor_y + 150, width + 600, 300, .{ .kind = .static, .color = wall_color });
        _ = try self.box(-150, height / 2, 300, height * 3, .{ .kind = .static, .color = wall_color });
        _ = try self.box(width + 150, height / 2, 300, height * 3, .{ .kind = .static, .color = wall_color });

        try scenarios[index].build(self);
    }

    /// Loads a scene in response to a key press and retitles the window.
    fn switchTo(self: *Lab, index: usize) void {
        self.load(index) catch |err| std.debug.print("could not load scene: {s}\n", .{@errorName(err)});
        sapp.setWindowTitle(titles[index]);
    }

    fn box(self: *Lab, x: f32, y: f32, w: f32, h: f32, options: Options) !EntityHandle {
        return self.ctx.world.spawn(.{
            .position = .init(x, y),
            .rotation = options.rotation,
            .body = .{
                .kind = options.kind,
                .shape = .rect(w, h),
                .mass = w * h / 900.0,
                .friction = options.friction,
                .restitution = options.restitution,
                .velocity = options.velocity,
            },
            .sprite = .{ .color = options.color },
        });
    }

    fn ball(self: *Lab, x: f32, y: f32, radius: f32, options: Options) !EntityHandle {
        return self.ctx.world.spawn(.{
            .position = .init(x, y),
            .body = .{
                .kind = options.kind,
                .shape = .circ(radius),
                .mass = std.math.pi * radius * radius / 900.0,
                .friction = options.friction,
                .restitution = options.restitution,
                .velocity = options.velocity,
            },
            .sprite = .{ .color = options.color },
        });
    }

    fn watch(self: *Lab, handle: EntityHandle, label: []const u8) !void {
        const position = self.ctx.world.get(handle).?.body.position;
        try self.probes.append(self.ctx.alloc, .{ .handle = handle, .label = label, .start = position });
    }

    // 1. A ball placed exactly on top of another round body is balanced on a
    // single point. Nothing pushes it sideways, so it should stay; one pixel
    // of offset should make it roll off.
    fn buildRoundOnRound(self: *Lab) !void {
        _ = try self.ball(130, floor_y - 40, 40, .{ .kind = .static, .color = prop_color });
        try self.watch(try self.ball(130, floor_y - 80 - 25, 25, .{ .color = palette[0] }), "ball centred on a fixed ball");

        _ = try self.ball(340, floor_y - 40, 40, .{ .color = palette[1] });
        try self.watch(try self.ball(340, floor_y - 80 - 25, 25, .{ .color = palette[0] }), "ball centred on a free ball");

        _ = try self.ball(550, floor_y - 40, 40, .{ .color = palette[1] });
        try self.watch(try self.ball(551, floor_y - 80 - 25, 25, .{ .color = palette[3] }), "ball 1 px off centre on a free ball");

        _ = try self.ball(760, floor_y - 30, 30, .{ .color = palette[1] });
        _ = try self.ball(760, floor_y - 90, 30, .{ .color = palette[2] });
        try self.watch(try self.ball(760, floor_y - 150, 30, .{ .color = palette[0] }), "top of three centred balls");
    }

    // 2. Stacks should come to rest and fall asleep without drifting.
    fn buildBoxStacks(self: *Lab) !void {
        inline for (.{ .{ 250, 5, "top of a 5 box stack" }, .{ 620, 10, "top of a 10 box stack" } }) |stack| {
            var top: EntityHandle = undefined;
            for (0..stack[1]) |i| {
                const y = floor_y - 20 - @as(f32, @floatFromInt(i)) * 40;
                top = try self.box(stack[0], y, 40, 40, .{ .color = palette[i % palette.len], .restitution = 0 });
            }
            try self.watch(top, stack[2]);
        }
    }

    // 3. The classic stability test: every box rests on two below it.
    fn buildPyramid(self: *Lab) !void {
        const rows = 8;
        const size: f32 = 36;
        var top: EntityHandle = undefined;
        for (0..rows) |row| {
            const count = rows - row;
            const y = floor_y - size / 2 - @as(f32, @floatFromInt(row)) * size;
            const left = width / 2 - @as(f32, @floatFromInt(count - 1)) * (size + 2) / 2;
            for (0..count) |i| {
                const x = left + @as(f32, @floatFromInt(i)) * (size + 2);
                top = try self.box(x, y, size, size, .{ .color = palette[row % palette.len], .restitution = 0 });
            }
        }
        try self.watch(top, "top of the pyramid");
    }

    // 4. The ramp rises about 21 degrees (tan = 0.38), so a body should stay
    // put when its friction with the ramp is above that and slide when below.
    fn buildRamp(self: *Lab) !void {
        const angle: f32 = 0.366;
        const centre = Vec2.init(430, 330);
        _ = try self.box(centre.x, centre.y, 660, 16, .{ .kind = .static, .rotation = angle, .friction = 0.9, .color = prop_color });

        const cases = .{
            .{ -250, 0.9, "box, friction 0.9" },
            .{ -90, 0.4, "box, friction 0.4" },
            .{ 70, 0.05, "box, friction 0.05" },
        };
        inline for (cases, 0..) |case, i| {
            // Place each box on the ramp surface, tilted to match it.
            const along = Vec2.init(@cos(angle), @sin(angle)).scale(case[0]);
            const up = Vec2.init(@sin(angle), -@cos(angle)).scale(8 + 15 + 0.5);
            const position = centre.add(along).add(up);
            const handle = try self.box(position.x, position.y, 30, 30, .{
                .rotation = angle,
                .friction = case[1],
                .restitution = 0,
                .color = palette[i],
            });
            try self.watch(handle, case[2]);
        }
        const along = Vec2.init(@cos(angle), @sin(angle)).scale(220);
        const up = Vec2.init(@sin(angle), -@cos(angle)).scale(8 + 14 + 0.5);
        const position = centre.add(along).add(up);
        try self.watch(try self.ball(position.x, position.y, 14, .{ .friction = 0.9, .color = palette[3] }), "ball, friction 0.9");
    }

    // 5. The same drop with different bounciness, from none to nearly perfect.
    fn buildRestitution(self: *Lab) !void {
        const values = [_]f32{ 0, 0.25, 0.5, 0.75, 0.95 };
        const labels = [_][]const u8{ "restitution 0", "restitution 0.25", "restitution 0.5", "restitution 0.75", "restitution 0.95" };
        for (values, labels, 0..) |restitution, label, i| {
            const x = 150 + @as(f32, @floatFromInt(i)) * 150;
            // A shelf with the same restitution as its ball, so the pair is unambiguous.
            _ = try self.box(x, floor_y - 10, 110, 20, .{ .kind = .static, .restitution = restitution, .color = prop_color });
            try self.watch(try self.ball(x, 150, 18, .{ .restitution = restitution, .color = palette[i] }), label);
        }
    }

    // 6. No gravity. Each bullet moves further per step than the one above
    // it; each wall is thinner than the one to its left.
    fn buildTunnelling(self: *Lab) !void {
        self.ctx.physics.cfg.gravity = Vec2.zero;
        const thicknesses = [_]f32{ 24, 10, 4 };
        const speeds = [_]f32{ 600, 1200, 2000 };
        const labels = [_][3][]const u8{
            .{ "600 px/s at a 24 px wall", "1200 px/s at a 24 px wall", "2000 px/s at a 24 px wall" },
            .{ "600 px/s at a 10 px wall", "1200 px/s at a 10 px wall", "2000 px/s at a 10 px wall" },
            .{ "600 px/s at a 4 px wall", "1200 px/s at a 4 px wall", "2000 px/s at a 4 px wall" },
        };
        for (thicknesses, 0..) |thickness, lane| {
            const lane_y = 110 + @as(f32, @floatFromInt(lane)) * 170;
            _ = try self.box(600, lane_y, thickness, 130, .{ .kind = .static, .color = prop_color });
            for (speeds, 0..) |speed, i| {
                const y = lane_y - 40 + @as(f32, @floatFromInt(i)) * 40;
                const handle = try self.ball(80, y, 8, .{
                    .velocity = .init(speed, 0),
                    .restitution = 0,
                    .color = palette[i],
                });
                try self.watch(handle, labels[lane][i]);
            }
        }
    }

    // 7. A general mess, to see settling and sleeping in bulk.
    fn buildPile(self: *Lab) !void {
        var random = std.Random.DefaultPrng.init(7);
        const r = random.random();
        for (0..140) |i| {
            const x = 150 + r.float(f32) * 600;
            const y = -400 + r.float(f32) * 800;
            const color = palette[i % palette.len];
            if (i % 2 == 0) {
                _ = try self.ball(x, y, 10 + r.float(f32) * 10, .{ .color = color });
            } else {
                _ = try self.box(x, y, 18 + r.float(f32) * 22, 18 + r.float(f32) * 22, .{
                    .rotation = r.float(f32) * std.math.pi,
                    .color = color,
                });
            }
        }
    }

    pub fn update(self: *Lab, _: f32) void {
        const input = self.ctx.input;
        const keys = [_]zixel.Key{ .@"1", .@"2", .@"3", .@"4", .@"5", .@"6", .@"7" };
        for (keys, 0..) |key, index| {
            if (input.isKeyPressed(key)) self.switchTo(index);
        }
        if (input.isKeyPressed(.r)) self.switchTo(self.current);

        const mouse = input.mousePosition();
        if (input.isMousePressed(.left)) {
            _ = self.ball(mouse.x, mouse.y, 14, .{ .color = palette[self.spawned % palette.len] }) catch {};
            self.spawned += 1;
        }
        if (input.isMousePressed(.right)) {
            _ = self.box(mouse.x, mouse.y, 30, 30, .{ .color = palette[self.spawned % palette.len] }) catch {};
            self.spawned += 1;
        }
    }

    pub fn render(self: *Lab) void {
        const renderer = self.ctx.renderer;
        for (self.ctx.world.slots.items) |*slot| {
            if (!slot.alive) continue;
            const sprite = slot.entity.sprite orelse continue;
            const body = &slot.entity.body;
            const dim: f32 = if (body.isSleeping()) 0.45 else 1.0;
            const color = Color{ .r = sprite.color.r * dim, .g = sprite.color.g * dim, .b = sprite.color.b * dim, .a = 1 };
            switch (body.shape) {
                .circle => |c| {
                    renderer.drawCircle(body.position.x, body.position.y, c.radius, color);
                    renderer.drawLine(
                        body.position.x,
                        body.position.y,
                        body.position.x + @cos(body.rotation) * c.radius,
                        body.position.y + @sin(body.rotation) * c.radius,
                        Color.black,
                    );
                },
                .rectangle => |r| renderer.drawRotatedRect(body.position.x, body.position.y, r.width, r.height, body.rotation, color),
            }
        }
    }

    /// Simulates the current scene without a window and prints what happened.
    fn measure(self: *Lab) void {
        const scenario = scenarios[self.current];
        const world = self.ctx.world;
        const physics = self.ctx.physics;
        const steps: usize = @intFromFloat(scenario.seconds / step_dt);
        for (0..steps) |_| physics.update(world.bodies(), physics.cfg.physics_time_step);

        var dynamic: u32 = 0;
        var asleep: u32 = 0;
        var escaped: u32 = 0;
        var max_speed: f32 = 0;
        var iter = world.bodies();
        while (iter.next()) |body| {
            if (body.kind != .dynamic) continue;
            dynamic += 1;
            if (body.isSleeping()) asleep += 1;
            max_speed = @max(max_speed, body.velocity.length());
            const p = body.position;
            if (p.x < 0 or p.x > width or p.y > floor_y or !std.math.isFinite(p.x) or !std.math.isFinite(p.y)) escaped += 1;
        }
        std.debug.print("\n{d}. {s}: after {d:.0} s, {d} of {d} bodies asleep, fastest {d:.1} px/s, {d} outside the walls\n", .{
            self.current + 1, scenario.name, scenario.seconds, asleep, dynamic, max_speed, escaped,
        });
        for (self.probes.items) |probe| {
            const body = &(world.get(probe.handle) orelse continue).body;
            const moved = body.position.sub(probe.start);
            std.debug.print("     {s:<36} moved x {d:>8.2}  y {d:>8.2}  speed {d:>7.2}  turned {d:>6.2} rad  {s}\n", .{
                probe.label,            moved.x,       moved.y,
                body.velocity.length(), body.rotation, if (body.isSleeping()) "asleep" else "awake",
            });
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const headless = args.len > 1 and std.mem.eql(u8, args[1], "--headless");

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    var engine = try Engine.init(debug_allocator.allocator(), .{
        .window = .{ .width = width, .height = height, .title = titles[0] },
        .physics = .{ .gravity = default_gravity },
    });
    try engine.createScene(Lab);

    if (headless) {
        const lab: *Lab = @ptrCast(@alignCast(engine.scene.?.ptr));
        for (0..scenarios.len) |index| {
            try lab.load(index);
            lab.measure();
        }
        engine.deinit();
    } else {
        engine.run();
    }
    _ = debug_allocator.deinit();
}
