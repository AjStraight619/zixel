const std = @import("std");
const Allocator = std.mem.Allocator;

const Grid = @import("Grid.zig").Grid;
const Astar = @import("astar.zig");

const World = @import("../../physics/world.zig");
const BodyHandle = World.BodyHandle;
const Body = @import("../../physics/body.zig").Body;

const Vec2 = @import("../../math/vec2.zig");

pub const Nav = @This();

alloc: Allocator,

grid: Grid,
scratch: Astar.Scratch,

agents: std.AutoHashMap(BodyHandle, AgentState),

pub const Config = struct {
    cell_size: f32 = 24,
    origin_x: f32 = 0,
    origin_y: f32 = 0,
    width: u32,
    height: u32,
};

pub const AgentParams = struct {
    speed: f32 = 140.0, // world units/sec
    arrive_radius: f32 = 6.0, // world units
    repath_period: f32 = 0.25, // seconds
};

const AgentState = struct {
    // goal stored as grid index (fast for A*)
    target_idx: ?u32 = null,

    // per-agent path + progress
    path: std.ArrayList(u32) = .empty,
    waypoint_i: usize = 0,

    // repath control
    needs_repath: bool = true,
    repath_cooldown: f32 = 0.0,

    // tuning
    params: AgentParams = .{},
};

pub fn init(alloc: Allocator, cfg: Config) !Nav {
    var grid = try Grid.init(
        alloc,
        cfg.width,
        cfg.height,
        cfg.cell_size,
        cfg.origin_x,
        cfg.origin_y,
    );

    const scratch = try Astar.Scratch.init(alloc, grid.cellCount());
    const agents = std.AutoHashMap(BodyHandle, AgentState).init(alloc);

    return .{
        .alloc = alloc,
        .grid = grid,
        .scratch = scratch,
        .agents = agents,
    };
}

pub fn deinit(self: *Nav) void {
    var it = self.agents.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.path.deinit(self.alloc);
    }
    self.agents.deinit();

    self.scratch.deinit(self.alloc);
    self.grid.deinit(self.alloc);
    self.* = undefined;
}

// -------------------------------------------------------------------------
// world <-> grid helpers
// -------------------------------------------------------------------------

pub fn worldToIdx(self: *const Nav, wx: f32, wy: f32) ?u32 {
    if (self.grid.worldToCell(wx, wy)) |c| return self.grid.idx(c.x, c.y);
    return null;
}

pub fn idxToWorldCenter(self: *const Nav, idx: u32) Grid.Point {
    const c = self.grid.xy(idx);
    return self.grid.cellCenter(c.x, c.y);
}

// -------------------------------------------------------------------------
// Bake statics: World -> grid.blocked[]
// -------------------------------------------------------------------------

pub fn rebuildBlockedFromWorld(self: *Nav, world: *const World) void {
    @memset(self.grid.blocked, false);

    const Ctx = struct { nav: *Nav };
    const ctx = Ctx{ .nav = self };

    world.forEachBodyConst(ctx, struct {
        fn f(ctx_: Ctx, body: *const Body) void {
            if (body.kind != .static) return;

            switch (body.shape) {
                .rectangle => |r| {
                    const tlx = body.position.x - (r.width * 0.5);
                    const tly = body.position.y - (r.height * 0.5);
                    ctx_.nav.grid.markRect(tlx, tly, r.width, r.height, true);
                },
                .circle => |c| {
                    const tlx = body.position.x - c.radius;
                    const tly = body.position.y - c.radius;
                    const d = c.radius * 2.0;
                    ctx_.nav.grid.markRect(tlx, tly, d, d, true);
                },
            }
        }
    }.f);

    // invalidate cached paths
    var it = self.agents.iterator();
    while (it.next()) |entry| entry.value_ptr.needs_repath = true;
}

// -------------------------------------------------------------------------
// Agent API (engine-like)
// -------------------------------------------------------------------------

pub fn ensureAgent(self: *Nav, handle: BodyHandle) *AgentState {
    const gop = self.agents.getOrPut(handle) catch unreachable;
    if (!gop.found_existing) gop.value_ptr.* = .{};
    return gop.value_ptr;
}

pub fn removeAgent(self: *Nav, handle: BodyHandle) void {
    if (self.agents.fetchRemove(handle)) |kv| {
        var st = kv.value;
        st.path.deinit(self.alloc);
    }
}

pub fn setAgentParams(self: *Nav, handle: BodyHandle, params: AgentParams) void {
    var st = self.ensureAgent(handle);
    st.params = params;
}

pub fn clearTarget(self: *Nav, handle: BodyHandle) void {
    var st = self.ensureAgent(handle);
    st.target_idx = null;
    st.path.clearRetainingCapacity();
    st.waypoint_i = 0;
}

/// Set goal from world coords (mouse click, AI destination, etc.)
pub fn setTargetWorld(self: *Nav, handle: BodyHandle, target: Vec2) void {
    var st = self.ensureAgent(handle);

    const goal = self.worldToIdx(target.x, target.y) orelse {
        self.clearTarget(handle);
        return;
    };

    st.target_idx = goal;
    st.needs_repath = true;
    st.repath_cooldown = 0.0;
    st.path.clearRetainingCapacity();
    st.waypoint_i = 0;
}

pub fn getPath(self: *const Nav, handle: BodyHandle) ?[]const u32 {
    const st = self.agents.getPtr(handle) orelse return null;
    return st.path.items;
}

/// Engine-style: update all registered agents.
pub fn update(self: *Nav, world: *World, dt: f32) void {
    var it = self.agents.iterator();
    while (it.next()) |entry| {
        const handle = entry.key_ptr.*;
        self.updateOne(world, handle, dt);
    }
}

fn updateOne(self: *Nav, world: *World, handle: BodyHandle, dt: f32) void {
    var st = self.agents.getPtr(handle) orelse return;
    const body = world.getBody(handle) orelse return;

    const goal = st.target_idx orelse return;

    // cooldown
    if (st.repath_cooldown > 0) st.repath_cooldown -= dt;

    // Do we need a fresh path?
    if (st.needs_repath or st.path.items.len == 0 or st.waypoint_i >= st.path.items.len) {
        if (st.repath_cooldown <= 0) {
            self.repathInternal(body.position, goal, st);
            st.repath_cooldown = st.params.repath_period;
        }
    }

    if (st.path.items.len == 0 or st.waypoint_i >= st.path.items.len) return;

    // Follow waypoint
    const wp_idx = st.path.items[st.waypoint_i];
    const wp = self.idxToWorldCenter(wp_idx);

    const dx = wp.x - body.position.x;
    const dy = wp.y - body.position.y;
    const dist2 = dx * dx + dy * dy;

    const r2 = st.params.arrive_radius * st.params.arrive_radius;
    if (dist2 <= r2) {
        st.waypoint_i += 1;
        return;
    }

    const dist = @sqrt(dist2);
    const vx = (dx / dist) * st.params.speed;
    const vy = (dy / dist) * st.params.speed;

    body.velocity = Vec2.init(vx, vy);
}

fn repathInternal(self: *Nav, pos: Vec2, goal: u32, st: *AgentState) void {
    const start = self.worldToIdx(pos.x, pos.y) orelse {
        st.path.clearRetainingCapacity();
        st.waypoint_i = 0;
        st.needs_repath = false;
        return;
    };

    st.path.clearRetainingCapacity();

    const ok = Astar.findPath(self.alloc, &self.grid, &self.scratch, start, goal, &st.path);
    if (!ok) {
        st.path.clearRetainingCapacity();
        st.waypoint_i = 0;
    } else {
        st.waypoint_i = 0;
    }

    st.needs_repath = false;
}
