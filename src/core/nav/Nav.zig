const std = @import("std");
const log = std.log.scoped(.zixel_nav);
const Allocator = std.mem.Allocator;

const Grid = @import("Grid.zig");
const astar = @import("astar.zig");

const World = @import("../../engine/World.zig");
const EntityHandle = World.EntityHandle;
const Body = @import("../../physics/Body.zig");

const Vec2 = @import("../../math/Vec2.zig");

const Nav = @This();

alloc: Allocator,

grid: Grid,
scratch: astar.Scratch,

agents: std.AutoHashMap(EntityHandle, AgentState),

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

    // status flags
    arrived: bool = false, // true when agent reached goal cell center

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
    errdefer grid.deinit(alloc);

    const scratch = try astar.Scratch.init(alloc, grid.cellCount());
    const agents = std.AutoHashMap(EntityHandle, AgentState).init(alloc);

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

/// Marks every cell overlapped by a static body's bounding box as blocked.
pub fn rebuildBlockedFromWorld(self: *Nav, world: *const World) void {
    @memset(self.grid.blocked, false);

    for (world.slots.items) |*slot| {
        if (!slot.alive) continue;
        const body: *const Body = &slot.entity.body;
        if (body.kind != .static) continue;

        // The bounding box accounts for rotation as well as shape.
        const box = body.aabb();
        self.grid.markRect(box.min.x, box.min.y, box.max.x - box.min.x, box.max.y - box.min.y, true);
    }

    // invalidate cached paths
    var it = self.agents.iterator();
    while (it.next()) |entry| entry.value_ptr.needs_repath = true;
}

// -------------------------------------------------------------------------
// Agent API (engine-like)
// -------------------------------------------------------------------------

/// Registers the agent if needed. Fails only when out of memory.
pub fn ensureAgent(self: *Nav, handle: EntityHandle) !*AgentState {
    const gop = try self.agents.getOrPut(handle);
    if (!gop.found_existing) gop.value_ptr.* = .{};
    return gop.value_ptr;
}

pub fn removeAgent(self: *Nav, handle: EntityHandle) void {
    if (self.agents.fetchRemove(handle)) |kv| {
        var st = kv.value;
        st.path.deinit(self.alloc);
    }
}

pub fn setAgentParams(self: *Nav, handle: EntityHandle, params: AgentParams) !void {
    var st = try self.ensureAgent(handle);
    st.params = params;
}

/// Stops an agent. Does nothing for a handle that was never registered.
pub fn clearTarget(self: *Nav, handle: EntityHandle) void {
    var st = self.agents.getPtr(handle) orelse return;
    st.target_idx = null;
    st.path.clearRetainingCapacity();
    st.waypoint_i = 0;
    st.arrived = false;
}

/// Set goal from world coords (mouse click, AI destination, etc.)
pub fn setTargetWorld(self: *Nav, handle: EntityHandle, target: Vec2) !void {
    var st = try self.ensureAgent(handle);

    const goal = self.worldToIdx(target.x, target.y) orelse {
        self.clearTarget(handle);
        return;
    };

    st.target_idx = goal;
    st.needs_repath = true;
    st.repath_cooldown = 0.0;
    st.path.clearRetainingCapacity();
    st.waypoint_i = 0;
    st.arrived = false; // Reset arrived flag for new target
}

pub fn getPath(self: *const Nav, handle: EntityHandle) ?[]const u32 {
    const st = self.agents.getPtr(handle) orelse return null;
    return st.path.items;
}

/// Check if agent has arrived at its goal.
/// User should handle this (e.g., stop velocity, trigger action).
/// Calling clearTarget() or setTargetWorld() will reset this.
pub fn hasArrived(self: *const Nav, handle: EntityHandle) bool {
    const st = self.agents.getPtr(handle) orelse return false;
    return st.arrived;
}

/// Check if agent is actively navigating (has a target and hasn't arrived)
pub fn isNavigating(self: *const Nav, handle: EntityHandle) bool {
    const st = self.agents.getPtr(handle) orelse return false;
    return st.target_idx != null and !st.arrived;
}

/// Check if agent has a target set (may or may not have arrived)
pub fn hasTarget(self: *const Nav, handle: EntityHandle) bool {
    const st = self.agents.getPtr(handle) orelse return false;
    return st.target_idx != null;
}

/// Update all registered agents.
pub fn update(self: *Nav, world: *World, dt: f32) void {
    var it = self.agents.iterator();
    while (it.next()) |entry| {
        const handle = entry.key_ptr.*;
        self.updateOne(world, handle, dt);
    }
}

fn updateOne(self: *Nav, world: *World, handle: EntityHandle, dt: f32) void {
    var st = self.agents.getPtr(handle) orelse return;
    const entity = world.get(handle) orelse return;
    const body = &entity.body;

    const goal = st.target_idx orelse return; // No target, nothing to do

    if (st.arrived) return;

    // cooldown
    if (st.repath_cooldown > 0) st.repath_cooldown -= dt;

    // Do we need a fresh path?
    if (st.needs_repath or st.path.items.len == 0 or st.waypoint_i >= st.path.items.len) {
        if (st.repath_cooldown <= 0) {
            self.repathInternal(body.position, goal, st);
            st.repath_cooldown = st.params.repath_period;
        }
    }

    if (st.path.items.len == 0 or st.waypoint_i >= st.path.items.len) {
        // No path or reached end of waypoints - check if we are at final goal center
        const goal_wp = self.idxToWorldCenter(goal);
        const gdx = goal_wp.x - body.position.x;
        const gdy = goal_wp.y - body.position.y;
        if (gdx * gdx + gdy * gdy <= st.params.arrive_radius * st.params.arrive_radius) {
            st.arrived = true;
        }
        return;
    }

    // Follow waypoint
    const wp_idx = st.path.items[st.waypoint_i];
    const wp = self.idxToWorldCenter(wp_idx);

    const dx = wp.x - body.position.x;
    const dy = wp.y - body.position.y;
    const dist2 = dx * dx + dy * dy;

    const r2 = st.params.arrive_radius * st.params.arrive_radius;
    if (dist2 <= r2) {
        st.waypoint_i += 1;
        // If this was the last waypoint, we've basically arrived (will be finalized next frame)
        if (st.waypoint_i >= st.path.items.len) {
            st.arrived = true;
        }
        return;
    }

    const dist = @sqrt(dist2);
    const vx = (dx / dist) * st.params.speed;
    const vy = (dy / dist) * st.params.speed;

    body.velocity = Vec2.init(vx, vy);
}

fn repathInternal(self: *Nav, pos: Vec2, goal: u32, st: *AgentState) void {
    const start = self.worldToIdx(pos.x, pos.y) orelse {
        log.debug("Agent position ({d:.1}, {d:.1}) outside grid", .{ pos.x, pos.y });
        st.path.clearRetainingCapacity();
        st.waypoint_i = 0;
        st.needs_repath = false;
        return;
    };

    log.debug("Repath: start={d} goal={d} start_blocked={} goal_blocked={}", .{
        start,
        goal,
        self.grid.isBlockedIdx(start),
        self.grid.isBlockedIdx(goal),
    });

    st.path.clearRetainingCapacity();

    const ok = astar.findPath(self.alloc, &self.grid, &self.scratch, start, goal, &st.path);
    if (!ok) {
        log.debug("No path from {d} to {d}", .{ start, goal });
        st.path.clearRetainingCapacity();
        st.waypoint_i = 0;
    } else {
        log.debug("Path found: length={d}", .{st.path.items.len});
        st.waypoint_i = 0;
    }

    st.needs_repath = false;
}

test "static bodies are baked into the grid and far-away targets are ignored" {
    const alloc = std.testing.allocator;
    var world = World.init(alloc);
    defer world.deinit();
    var nav = try Nav.init(alloc, .{ .cell_size = 10, .width = 8, .height = 8 });
    defer nav.deinit();

    // One cell exactly, plus a dynamic body that must not block anything.
    _ = try world.addStaticRect(15, 15, 10, 10, .{});
    const agent = try world.addDynamicCircle(55, 55, 3, .{});
    nav.rebuildBlockedFromWorld(&world);
    var blocked: usize = 0;
    for (nav.grid.blocked) |b| blocked += @intFromBool(b);
    try std.testing.expectEqual(@as(usize, 1), blocked);
    try std.testing.expect(nav.grid.isBlocked(1, 1));

    try nav.setTargetWorld(agent, Vec2.init(5, 5));
    try std.testing.expect(nav.hasTarget(agent));
    nav.update(&world, 1.0 / 60.0);
    try std.testing.expect(nav.getPath(agent).?.len > 0);

    // A target (or an agent) flung far outside the grid is not a crash.
    try nav.setTargetWorld(agent, Vec2.init(1e12, 5));
    try std.testing.expect(!nav.hasTarget(agent));
    try nav.setTargetWorld(agent, Vec2.init(5, 5));
    world.getBody(agent).?.position = Vec2.init(1e12, std.math.nan(f32));
    nav.update(&world, 1.0 / 60.0);
    try std.testing.expectEqual(@as(usize, 0), nav.getPath(agent).?.len);
}

fn navInitWithFailures(alloc: Allocator) !void {
    var nav = try Nav.init(alloc, .{ .width = 4, .height = 4 });
    nav.deinit();
}

test "nav init cleans up on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, navInitWithFailures, .{});
}
