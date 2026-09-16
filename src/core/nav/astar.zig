const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;
const Order = std.math.Order;
const ArrayList = std.ArrayList;

pub const NO_PARENT: u32 = std.math.maxInt(u32);

pub const Scratch = struct {
    g_score: []f32,
    parent: []u32,
    closed: []bool,

    open: std.PriorityQueue(OpenNode, void, compare),

    const OpenNode = struct {
        f: f32,
        idx: u32,
    };

    fn compare(_: void, a: OpenNode, b: OpenNode) Order {
        if (a.f < b.f) return .lt;
        if (a.f > b.f) return .gt;
        return .eq;
    }

    pub fn init(alloc: Allocator, cell_count: usize) !Scratch {
        var scratch = Scratch{
            .g_score = try alloc.alloc(f32, cell_count),
            .parent = try alloc.alloc(u32, cell_count),
            .closed = try alloc.alloc(bool, cell_count),
            .open = std.PriorityQueue(OpenNode, void, compare).initContext({}),
        };
        scratch.reset();
        return scratch;
    }

    pub fn reset(self: *Scratch) void {
        for (self.g_score) |*g| g.* = math.inf(f32);
        for (self.parent) |*p| p.* = NO_PARENT;
        @memset(self.closed, false);
        self.open.clearRetainingCapacity();
    }

    pub fn deinit(self: *Scratch, alloc: Allocator) void {
        alloc.free(self.g_score);
        alloc.free(self.parent);
        alloc.free(self.closed);
        self.open.deinit(alloc);
    }
};

fn baseType(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .pointer => |p| p.child,
        else => T,
    };
}

/// Require:
/// - width: u32
/// - height: u32
/// - isBlockedIdx(self, idx: u32) bool
/// - tryNeighbor4(self, idx: u32, dir: u2) ?u32
fn assertGridContract(comptime G: type) void {
    comptime {
        if (!@hasField(G, "width")) @compileError("A*: grid must have field `width: u32`.");
        if (!@hasField(G, "height")) @compileError("A*: grid must have field `height: u32`.");

        if (@TypeOf(@field(@as(G, undefined), "width")) != u32)
            @compileError("A*: grid.width must be u32.");
        if (@TypeOf(@field(@as(G, undefined), "height")) != u32)
            @compileError("A*: grid.height must be u32.");

        if (!@hasDecl(G, "isBlockedIdx"))
            @compileError("A*: grid must declare `pub fn isBlockedIdx(self: *const G, idx: u32) bool`.");
        if (!@hasDecl(G, "tryNeighbor4"))
            @compileError("A*: grid must declare `pub fn tryNeighbor4(self: *const G, idx: u32, dir: u2) ?u32`.");

        // Validate isBlockedIdx signature
        {
            const FnT = @TypeOf(G.isBlockedIdx);
            const ti = @typeInfo(FnT);
            if (ti != .@"fn") @compileError("A*: grid.isBlockedIdx must be a function.");
            const fninfo = ti.@"fn";
            if (fninfo.params.len != 2) @compileError("A*: isBlockedIdx must take (self, idx).");
            const idx_param = fninfo.params[1].type orelse @compileError("A*: isBlockedIdx idx param missing type.");
            if (idx_param != u32) @compileError("A*: isBlockedIdx idx must be u32.");
            const ret = fninfo.return_type orelse @compileError("A*: isBlockedIdx return type missing.");
            if (ret != bool) @compileError("A*: isBlockedIdx must return bool.");
        }

        // Validate tryNeighbor4 signature
        {
            const FnT = @TypeOf(G.tryNeighbor4);
            const ti = @typeInfo(FnT);
            if (ti != .@"fn") @compileError("A*: grid.tryNeighbor4 must be a function.");
            const fninfo = ti.@"fn";
            if (fninfo.params.len != 3) @compileError("A*: tryNeighbor4 must take (self, idx, dir).");

            const idx_param = fninfo.params[1].type orelse @compileError("A*: tryNeighbor4 idx param missing type.");
            if (idx_param != u32) @compileError("A*: tryNeighbor4 idx must be u32.");

            const dir_param = fninfo.params[2].type orelse @compileError("A*: tryNeighbor4 dir param missing type.");
            if (dir_param != u2) @compileError("A*: tryNeighbor4 dir must be u2 (0..3).");

            const ret = fninfo.return_type orelse @compileError("A*: tryNeighbor4 return type missing.");
            // ret must be ?u32
            if (ret != ?u32) @compileError("A*: tryNeighbor4 must return ?u32.");
        }
    }
}

fn heuristic(a: u32, b: u32, width: u32) f32 {
    const ax: u32 = a % width;
    const ay: u32 = a / width;
    const bx: u32 = b % width;
    const by: u32 = b / width;

    const dx: i32 = @as(i32, @intCast(ax)) - @as(i32, @intCast(bx));
    const dy: i32 = @as(i32, @intCast(ay)) - @as(i32, @intCast(by));
    return @floatFromInt(@abs(dx) + @abs(dy));
}

fn reconstructPath(
    alloc: Allocator,
    scratch: *const Scratch,
    start: u32,
    goal: u32,
    out_path: *std.ArrayList(u32),
) bool {
    var cur: u32 = goal;

    while (true) {
        out_path.append(alloc, cur) catch return false;
        if (cur == start) break;

        const p = scratch.parent[cur];
        if (p == NO_PARENT) return false;
        cur = p;
    }

    std.mem.reverse(u32, out_path.items);
    return true;
}

/// Grid-based 4-neighbor A* using grid.tryNeighbor4().
pub fn findPath(
    alloc: Allocator,
    grid: anytype,
    scratch: *Scratch,
    start: u32,
    goal: u32,
    out_path: *std.ArrayList(u32),
) bool {
    const G = baseType(@TypeOf(grid));
    assertGridContract(G);

    const width: u32 = grid.width;
    const height: u32 = grid.height;
    const cell_count: u32 = width * height;

    if (start >= cell_count or goal >= cell_count) return false;
    if (grid.isBlockedIdx(start) or grid.isBlockedIdx(goal)) return false;

    // Reset per-search state
    scratch.reset();
    out_path.clearRetainingCapacity();

    // Init
    scratch.g_score[start] = 0;
    scratch.parent[start] = NO_PARENT;
    const f0 = heuristic(start, goal, width);
    scratch.open.push(alloc, .{ .f = f0, .idx = start }) catch return false;

    while (scratch.open.count() > 0) {
        const node = scratch.open.pop().?;
        const current: u32 = node.idx;

        // Because we may insert duplicates (no decrease-key), skip stale entries.
        if (scratch.closed[current]) continue;

        if (current == goal) {
            return reconstructPath(alloc, scratch, start, goal, out_path);
        }

        scratch.closed[current] = true;

        const cur_g = scratch.g_score[current];

        // 4-way neighbors via grid helper
        for (0..4) |d_| {
            const d: u2 = @intCast(d_);
            const nb = grid.tryNeighbor4(current, d) orelse continue;

            if (scratch.closed[nb]) continue;
            if (grid.isBlockedIdx(nb)) continue;

            // Uniform move cost = 1 per step (change later for weights)
            const tentative = cur_g + 1.0;

            if (tentative < scratch.g_score[nb]) {
                scratch.g_score[nb] = tentative;
                scratch.parent[nb] = current;

                const f = tentative + heuristic(nb, goal, width);
                scratch.open.push(alloc, .{ .f = f, .idx = nb }) catch return false;
            }
        }
    }

    return false;
}

test "priority queue finds a shortest path around a blocked cell" {
    const Grid = @import("Grid.zig");
    const alloc = std.testing.allocator;
    var grid = try Grid.init(alloc, 3, 3, 1, 0, 0);
    defer grid.deinit(alloc);
    grid.setBlocked(1, 1, true);
    var scratch = try Scratch.init(alloc, grid.cellCount());
    defer scratch.deinit(alloc);
    var path: std.ArrayList(u32) = .empty;
    defer path.deinit(alloc);
    try std.testing.expect(findPath(alloc, &grid, &scratch, 0, 8, &path));
    try std.testing.expectEqual(@as(usize, 5), path.items.len);
    try std.testing.expectEqual(@as(u32, 0), path.items[0]);
    try std.testing.expectEqual(@as(u32, 8), path.items[4]);
    for (path.items) |cell| try std.testing.expect(cell != 4);
    // Reuse the scratch queue in the opposite direction.
    try std.testing.expect(findPath(alloc, &grid, &scratch, 8, 0, &path));
    try std.testing.expectEqual(@as(u32, 0), path.items[path.items.len - 1]);
}
