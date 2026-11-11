const std = @import("std");
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;

const Engine = zixel.Engine;
const Vec2 = zixel.Vec2;
const Color = zixel.Color;
const PhysicsShape = zixel.PhysicsShape;
const Entity = zixel.Entity;

const Nav = zixel.core.nav.Nav;
const Grid = zixel.core.nav.Grid;

pub const NavMazeScene = struct {
    pub const name = "astar_example";
    pub const is_blocking = false;
    pub const is_opaque = false;

    ctx: Engine.Ctx,
    nav: Nav,
    wall_thickness: f32 = 8.0,
    rng: std.Random,

    const grid_config: Nav.Config = .{
        .width = 25,
        .height = 18,
        .cell_size = 28,
        .origin_x = 40,
        .origin_y = 40,
    };

    pub fn init(ctx: Engine.Ctx) !NavMazeScene {
        var prng = std.Random.DefaultPrng.init(0xC0FFEE);

        var scene = NavMazeScene{
            .ctx = ctx,
            .nav = try Nav.init(ctx.alloc, grid_config),
            .rng = prng.random(),
        };

        try scene.rebuildMaze();
        return scene;
    }

    inline fn grid(self: *const NavMazeScene) *const Grid {
        return &self.nav.grid;
    }

    fn getAgentHandle(self: *NavMazeScene) ?zixel.EntityHandle {
        // Get handle by looking up in name index
        if (self.ctx.world.*.name_index.get("agent")) |h| {
            return h;
        }
        return null;
    }

    pub fn update(self: *NavMazeScene, dt: f32) void {
        // Click to move
        if (self.ctx.input.isMousePressed(.left)) {
            const p = self.ctx.input.mousePosition();
            if (self.getAgentHandle()) |h| {
                self.nav.setTargetWorld(h, Vec2.init(p.x, p.y));
            }
        }

        // M: regenerate a new maze
        if (self.ctx.input.isKeyPressed(.m)) {
            const s = self.rng.int(u64);
            var prng = std.Random.DefaultPrng.init(s);
            self.rng = prng.random();

            self.rebuildMaze() catch |err| {
                std.log.scoped(.game).err("rebuildMaze failed: {}", .{err});
            };
        }

        // Update navigation
        self.nav.update(self.ctx.world, dt);

        // Handle arrival
        if (self.getAgentHandle()) |h| {
            if (self.nav.hasArrived(h)) {
                if (self.ctx.world.*.getByName("agent")) |agent| {
                    agent.body.velocity = Vec2.zero;
                }
                self.nav.clearTarget(h);
            }
        }
    }

    pub fn render(self: *NavMazeScene) void {
        // World renders all entities
        zixel.drawEntities(self.ctx.renderer, self.ctx.world);

        // Draw path dots
        if (self.getAgentHandle()) |h| {
            if (self.nav.getPath(h)) |cells| {
                for (cells) |idx| {
                    const wp = self.nav.idxToWorldCenter(idx);
                    self.ctx.renderer.drawCircle(wp.x, wp.y, 3, Color{ .r = 0.95, .g = 0.9, .b = 0.25, .a = 1 });
                }
            }
        }
    }

    pub fn deinit(self: *NavMazeScene, alloc: Allocator) void {
        self.ctx.world.*.removeByOwner(.{ .scene = name });
        self.nav.deinit();
        alloc.destroy(self);
    }

    fn rebuildMaze(self: *NavMazeScene) !void {
        self.ctx.world.*.removeByOwner(.{ .scene = name });

        if (self.nav.grid.edges_h == null) {
            try self.nav.grid.initEdges(self.ctx.alloc);
        } else {
            @memset(self.nav.grid.edges_h.?, false);
            @memset(self.nav.grid.edges_v.?, false);
        }

        @memset(self.nav.grid.blocked, false);

        try self.buildLevel();

        if (self.getAgentHandle()) |h| {
            _ = self.nav.ensureAgent(h);
            self.nav.setAgentParams(h, .{
                .speed = 150,
                .arrive_radius = 8,
                .repath_period = 0.15,
            });
        }
    }

    fn buildLevel(self: *NavMazeScene) !void {
        const wall_color = Color{ .r = 0.85, .g = 0.85, .b = 0.88, .a = 1 };
        const frame_color = Color{ .r = 0.25, .g = 0.95, .b = 0.35, .a = 1 };
        const agent_color = Color{ .r = 0.35, .g = 0.75, .b = 0.95, .a = 1 };

        try self.spawnDebugFrame(frame_color);
        try self.spawnMazeWalls(wall_color);

        const start = self.cellCenter(0, 0);
        _ = try self.ctx.world.*.spawn(.{
            .name = "agent",
            .owner = .{ .scene = name },
            .position = start,
            .body = .{
                .kind = .dynamic,
                .shape = PhysicsShape.circ(8.0),
                .mass = 1.0,
                .friction = 0.1,
                .restitution = 0.0,
            },
            .sprite = .{ .color = agent_color },
        });
    }

    fn spawnDebugFrame(self: *NavMazeScene, c: Color) !void {
        const g = self.grid();
        const maze_w_px = @as(f32, @floatFromInt(g.width)) * g.cell_size;
        const maze_h_px = @as(f32, @floatFromInt(g.height)) * g.cell_size;

        const left = g.origin_x;
        const top = g.origin_y;
        const right = g.origin_x + maze_w_px;
        const bottom = g.origin_y + maze_h_px;

        const t: f32 = 6.0;

        try self.spawnWallRect((left + right) * 0.5, top - t * 0.5, (right - left) + t, t, c);
        try self.spawnWallRect((left + right) * 0.5, bottom + t * 0.5, (right - left) + t, t, c);
        try self.spawnWallRect(left - t * 0.5, (top + bottom) * 0.5, t, (bottom - top) + t, c);
        try self.spawnWallRect(right + t * 0.5, (top + bottom) * 0.5, t, (bottom - top) + t, c);
    }

    const Cell = struct {
        visited: bool = false,
        n: bool = true,
        e: bool = true,
        s: bool = true,
        w: bool = true,
    };

    fn cellIndex(self: *const NavMazeScene, x: u32, y: u32) usize {
        return @as(usize, y) * @as(usize, self.grid().width) + @as(usize, x);
    }

    fn cellCenter(self: *const NavMazeScene, x: u32, y: u32) Vec2 {
        const p = self.grid().cellCenter(x, y);
        return Vec2.init(p.x, p.y);
    }

    fn spawnMazeWalls(self: *NavMazeScene, wall_color: Color) !void {
        const g = self.grid();
        const count: usize = @as(usize, g.width) * @as(usize, g.height);
        const cells = try self.ctx.alloc.alloc(Cell, count);
        defer self.ctx.alloc.free(cells);

        @memset(cells, Cell{});
        self.generateMazeDFS(cells);

        const w = g.cell_size;
        const t = self.wall_thickness;

        for (0..g.height) |yy| {
            const y: u32 = @intCast(yy);
            for (0..g.width) |xx| {
                const x: u32 = @intCast(xx);
                const c = cells[self.cellIndex(x, y)];
                const center = self.cellCenter(x, y);

                if (c.n) {
                    try self.spawnWallRect(center.x, center.y - w * 0.5, w + t, t, wall_color);
                    self.nav.grid.setWallNorth(x, y, true);
                }
                if (c.w) {
                    try self.spawnWallRect(center.x - w * 0.5, center.y, t, w + t, wall_color);
                    self.nav.grid.setWallWest(x, y, true);
                }
                if (c.e) {
                    self.nav.grid.setWallEast(x, y, true);
                }
                if (c.s) {
                    self.nav.grid.setWallSouth(x, y, true);
                }

                if (y + 1 == g.height and c.s) {
                    try self.spawnWallRect(center.x, center.y + w * 0.5, w + t, t, wall_color);
                }
                if (x + 1 == g.width and c.e) {
                    try self.spawnWallRect(center.x + w * 0.5, center.y, t, w + t, wall_color);
                }
            }
        }
    }

    fn spawnWallRect(self: *NavMazeScene, cx: f32, cy: f32, w: f32, h: f32, wall_color: Color) !void {
        _ = try self.ctx.world.*.spawn(.{
            .owner = .{ .scene = name },
            .position = Vec2.init(cx, cy),
            .body = .{ .kind = .static, .shape = PhysicsShape.rect(w, h) },
            .sprite = .{ .color = wall_color },
        });
    }

    fn generateMazeDFS(self: *NavMazeScene, cells: []Cell) void {
        const g = self.grid();
        const w = g.width;
        const h = g.height;

        var stack: std.ArrayList(struct { x: u32, y: u32 }) = .empty;
        defer stack.deinit(self.ctx.alloc);

        var cx: u32 = self.rng.uintLessThan(u32, w);
        var cy: u32 = self.rng.uintLessThan(u32, h);

        cells[self.cellIndex(cx, cy)].visited = true;
        stack.append(self.ctx.alloc, .{ .x = cx, .y = cy }) catch return;

        while (stack.items.len > 0) {
            const top = stack.items[stack.items.len - 1];
            cx = top.x;
            cy = top.y;

            var nbs: [4]struct { x: u32, y: u32, dir: u2 } = undefined;
            var n: usize = 0;

            if (cy > 0 and !cells[self.cellIndex(cx, cy - 1)].visited) {
                nbs[n] = .{ .x = cx, .y = cy - 1, .dir = 0 };
                n += 1;
            }
            if (cx + 1 < w and !cells[self.cellIndex(cx + 1, cy)].visited) {
                nbs[n] = .{ .x = cx + 1, .y = cy, .dir = 1 };
                n += 1;
            }
            if (cy + 1 < h and !cells[self.cellIndex(cx, cy + 1)].visited) {
                nbs[n] = .{ .x = cx, .y = cy + 1, .dir = 2 };
                n += 1;
            }
            if (cx > 0 and !cells[self.cellIndex(cx - 1, cy)].visited) {
                nbs[n] = .{ .x = cx - 1, .y = cy, .dir = 3 };
                n += 1;
            }

            if (n == 0) {
                _ = stack.pop();
                continue;
            }

            const pick = self.rng.uintLessThan(usize, n);
            const nb = nbs[pick];

            var a = &cells[self.cellIndex(cx, cy)];
            var b = &cells[self.cellIndex(nb.x, nb.y)];

            switch (nb.dir) {
                0 => {
                    a.n = false;
                    b.s = false;
                },
                1 => {
                    a.e = false;
                    b.w = false;
                },
                2 => {
                    a.s = false;
                    b.n = false;
                },
                3 => {
                    a.w = false;
                    b.e = false;
                },
            }

            b.visited = true;
            stack.append(self.ctx.alloc, .{ .x = nb.x, .y = nb.y }) catch return;
        }
    }
};

pub fn main() !void {
    var engine = try Engine.init(std.heap.page_allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Nav Maze - Click: move | M: new maze",
        },
        .physics = .{
            .gravity = Vec2.init(0, 0),
            .linear_damping = 0.02,
            .allow_sleeping = false,
        },
    });

    try engine.createScene(NavMazeScene);
    engine.run();
}
