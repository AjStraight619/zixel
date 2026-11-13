//! Persistence demo. The first level creates the player and attaches `Stats`
//! to it as user data. That level is then torn down, entities and all, and the
//! player and its stats carry on into the next level.
//!
//!   zig build run-persist-example                  windowed
//!   zig build run-persist-example -- --headless    scripted, prints a transcript
const std = @import("std");
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;

const Engine = zixel.Engine;
const Vec2 = zixel.Vec2;
const Color = zixel.Color;
const Entity = zixel.Entity;

const player_name = "player";
const player_start = Vec2.init(90, 480);
const coin_count = 5;
const coin_color = Color{ .r = 1.0, .g = 0.82, .b = 0.2, .a = 1 };

/// Lives on the player entity. `born_in` is heap memory the stats own, to show
/// that everything behind the user data survives the scene that created it.
const Stats = struct {
    coins: u32 = 0,
    levels_entered: u32 = 0,
    born_in: []u8,

    pub fn deinit(self: *Stats, alloc: Allocator) void {
        std.debug.print("  stats released with the player (coins={d})\n", .{self.coins});
        alloc.free(self.born_in);
    }
};

fn coinPosition(level: u8, index: usize) Vec2 {
    const i: f32 = @floatFromInt(index);
    return if (level == 1) Vec2.init(220 + i * 110, 500) else Vec2.init(700 - i * 120, 500);
}

fn Level(comptime number: u8) type {
    return struct {
        const Self = @This();

        pub const name = std.fmt.comptimePrint("level_{d}", .{number});
        pub const is_blocking = false;
        pub const is_opaque = false;

        const tint: Color = if (number == 1)
            .{ .r = 0.25, .g = 0.55, .b = 0.35, .a = 1 }
        else
            .{ .r = 0.5, .g = 0.3, .b = 0.65, .a = 1 };

        ctx: Engine.Ctx,
        coins: [coin_count]?Vec2,

        pub fn init(ctx: Engine.Ctx) !Self {
            const world = ctx.world;
            const owner: Entity.Owner = .{ .scene = name };

            // Level geometry belongs to this scene and goes away with it.
            _ = try world.spawn(.{
                .owner = owner,
                .position = .init(400, 570),
                .body = .{ .kind = .static, .shape = .rect(800, 60) },
                .sprite = .{ .color = tint },
            });
            for ([_]f32{ -15, 815 }) |x| {
                _ = try world.spawn(.{
                    .owner = owner,
                    .position = .init(x, 300),
                    .body = .{ .kind = .static, .shape = .rect(30, 600) },
                });
            }
            for (0..3) |i| {
                const fi: f32 = @floatFromInt(i);
                _ = try world.spawn(.{
                    .owner = owner,
                    .position = .init(if (number == 1) 520 + fi * 60 else 140 + fi * 60, 200 - fi * 50),
                    .body = .{ .shape = .rect(36, 36), .restitution = 0.1 },
                    .sprite = .{ .color = .{ .r = tint.r + 0.25, .g = tint.g + 0.25, .b = tint.b + 0.25, .a = 1 } },
                });
            }

            // The player is created once, by whichever level runs first, and is
            // owned by no scene.
            if (world.getByName(player_name) == null) {
                const handle = try world.spawn(.{
                    .name = player_name,
                    .position = player_start,
                    .body = .{ .shape = .circ(16), .restitution = 0, .friction = 0.2 },
                    .sprite = .{ .color = .{ .r = 0.3, .g = 0.6, .b = 1.0, .a = 1 } },
                });
                const born_in = try world.alloc.dupe(u8, name);
                errdefer world.alloc.free(born_in);
                world.get(handle).?.user_data = try .init(world.alloc, Stats, .{ .born_in = born_in });
            }

            const player = world.getByName(player_name).?;
            player.body.position = player_start;
            player.body.velocity = Vec2.zero;
            if (player.user_data.as(Stats)) |stats| stats.levels_entered += 1;

            var self = Self{ .ctx = ctx, .coins = undefined };
            for (&self.coins, 0..) |*coin, i| coin.* = coinPosition(number, i);
            return self;
        }

        pub fn update(self: *Self, _: f32) void {
            const player = self.ctx.world.getByName(player_name) orelse return;
            const input = self.ctx.input;

            var move: f32 = 0;
            if (input.isKeyDown(.a) or input.isKeyDown(.left)) move -= 1;
            if (input.isKeyDown(.d) or input.isKeyDown(.right)) move += 1;
            if (move != 0) player.body.velocity.x = move * 260;
            const jump = input.isKeyPressed(.space) or input.isKeyPressed(.w) or input.isKeyPressed(.up);
            if (jump and @abs(player.body.velocity.y) < 20) player.body.velocity.y = -420;

            const stats = player.user_data.as(Stats) orelse return;
            for (&self.coins) |*coin| {
                const position = coin.* orelse continue;
                if (position.distance(player.body.position) < 30) {
                    coin.* = null;
                    stats.coins += 1;
                }
            }
        }

        pub fn render(self: *Self) void {
            for (self.coins) |coin| {
                if (coin) |position| self.ctx.renderer.drawCircle(position.x, position.y, 8, coin_color);
            }
        }

        pub fn deinit(self: *Self, _: Allocator) void {
            self.ctx.world.removeByOwner(.{ .scene = name });
        }
    };
}

/// Root scene. It never owns the player; it only swaps the level beneath it
/// and draws the world and the HUD.
const Game = struct {
    pub const name = "game";
    pub const is_blocking = false;
    pub const is_opaque = false;

    engine: *Engine,
    level: u8 = 1,

    pub fn init(_: Engine.Ctx, engine: *Engine) !Game {
        return .{ .engine = engine };
    }

    pub fn update(self: *Game, _: f32) void {
        const input = &self.engine.input;
        if (input.isKeyPressed(.enter) or input.isKeyPressed(.n)) {
            self.nextLevel() catch |err| std.debug.print("could not change level: {s}\n", .{@errorName(err)});
        }
    }

    /// Tears the current level down and builds the other one.
    pub fn nextLevel(self: *Game) !void {
        const before = self.engine.world.entityCount();
        if (self.level == 1) {
            self.engine.removeScene(Level(1).name);
            const between = self.engine.world.entityCount();
            try self.engine.pushCreateScene(Level(2));
            self.level = 2;
            std.debug.print("level 1 torn down: {d} entities -> {d}; level 2 built\n", .{ before, between });
        } else {
            self.engine.removeScene(Level(2).name);
            const between = self.engine.world.entityCount();
            try self.engine.pushCreateScene(Level(1));
            self.level = 1;
            std.debug.print("level 2 torn down: {d} entities -> {d}; level 1 built\n", .{ before, between });
        }
        self.report();
    }

    pub fn report(self: *Game) void {
        const world = &self.engine.world;
        const player = world.getByName(player_name) orelse return;
        const stats = player.user_data.as(Stats) orelse return;
        std.debug.print("  in level {d}: entities={d}  player coins={d} levels_entered={d} born_in={s}\n", .{
            self.level, world.entityCount(), stats.coins, stats.levels_entered, stats.born_in,
        });
    }

    pub fn render(self: *Game) void {
        const renderer = &self.engine.renderer;
        zixel.drawEntities(renderer, &self.engine.world);

        // HUD, read straight from the player's user data.
        const player = self.engine.world.getByName(player_name) orelse return;
        const stats = player.user_data.as(Stats) orelse return;
        for (0..stats.coins) |i| {
            renderer.drawRect(20 + @as(f32, @floatFromInt(i)) * 18, 20, 12, 12, coin_color);
        }
        for (0..stats.levels_entered) |i| {
            renderer.drawRect(20 + @as(f32, @floatFromInt(i)) * 18, 42, 12, 5, Color.white);
        }
    }

    pub fn deinit(_: *Game, _: Allocator) void {}
};

/// Walks the player onto `count` coins of the current level by running the
/// level's own update, without a window.
fn collectCoins(engine: *Engine, game: *Game, count: usize) void {
    const player = engine.world.getByName(player_name).?;
    for (0..count) |i| {
        player.body.position = coinPosition(game.level, i);
        engine.scene.?.children.items[0].update(1.0 / 60.0);
    }
    std.debug.print("collected {d} coins\n", .{count});
    game.report();
}

fn runHeadless(engine: *Engine) !void {
    const game: *Game = @ptrCast(@alignCast(engine.scene.?.ptr));
    std.debug.print("level 1 built; it created the player and its stats\n", .{});
    game.report();
    collectCoins(engine, game, 3);
    try game.nextLevel();
    collectCoins(engine, game, 2);
    try game.nextLevel();
    std.debug.print("shutting down\n", .{});
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const headless = args.len > 1 and std.mem.eql(u8, args[1], "--headless");

    // Reports leaks and double frees when the demo exits.
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

    var engine = try Engine.init(debug_allocator.allocator(), .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Persistence - A/D: move, Space: jump, Enter: next level",
        },
        .physics = .{
            .gravity = Vec2.init(0, 700),
            .allow_sleeping = false,
        },
    });
    try engine.createSceneWith(Game, .{&engine});
    try engine.pushCreateScene(Level(1));

    if (headless) {
        try runHeadless(&engine);
        engine.deinit();
    } else {
        // The window's cleanup callback tears the engine down.
        engine.run();
    }

    const leaked = debug_allocator.deinit() == .leak;
    std.debug.print("allocator check: {s}\n", .{if (leaked) "LEAKED" else "no leaks"});
}
