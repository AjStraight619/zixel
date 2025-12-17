const std = @import("std");
const time = std.time;
const Allocator = std.mem.Allocator;

/// Scene-owned navigation grid.
/// Supports both cell-based blocking (obstacles) and edge-based blocking (walls/mazes).
pub const Grid = @This();

pub const Point = struct { x: f32, y: f32 }; // world-space
pub const Cell = struct { x: u32, y: u32 }; // grid-space

/// Direction for edge-based movement
pub const Dir = enum(u2) {
    west = 0, // left
    east = 1, // right
    north = 2, // up
    south = 3, // down
};

width: u32,
height: u32,

cell_size: f32,
origin_x: f32 = 0,
origin_y: f32 = 0,

blocked: []bool, // len = width*height (cell-based blocking)

// Edge-based blocking for mazes/thin walls
// edges_h[y * width + x] = wall on NORTH edge of cell (x, y)
// edges_v[y * width + x] = wall on WEST edge of cell (x, y)
edges_h: ?[]bool = null, // horizontal walls (north/south), len = width * (height+1)
edges_v: ?[]bool = null, // vertical walls (east/west), len = (width+1) * height

pub fn init(
    alloc: Allocator,
    width: u32,
    height: u32,
    cell_size: f32,
    origin_x: f32,
    origin_y: f32,
) !Grid {
    const count: usize = @as(usize, width) * @as(usize, height);
    const blocked = try alloc.alloc(bool, count);
    @memset(blocked, false);
    return .{
        .width = width,
        .height = height,
        .cell_size = cell_size,
        .origin_x = origin_x,
        .origin_y = origin_y,
        .blocked = blocked,
        .edges_h = null,
        .edges_v = null,
    };
}

/// Initialize edge arrays for maze/thin-wall support
pub fn initEdges(self: *Grid, alloc: Allocator) !void {
    // Horizontal edges: width cells * (height+1) rows
    const h_count = @as(usize, self.width) * (@as(usize, self.height) + 1);
    self.edges_h = try alloc.alloc(bool, h_count);
    @memset(self.edges_h.?, false);

    // Vertical edges: (width+1) columns * height rows
    const v_count = (@as(usize, self.width) + 1) * @as(usize, self.height);
    self.edges_v = try alloc.alloc(bool, v_count);
    @memset(self.edges_v.?, false);
}

pub fn deinit(self: *Grid, alloc: Allocator) void {
    alloc.free(self.blocked);
    if (self.edges_h) |h| alloc.free(h);
    if (self.edges_v) |v| alloc.free(v);
    self.* = undefined;
}

pub fn cellCount(self: *const Grid) usize {
    return @as(usize, self.width) * @as(usize, self.height);
}

pub fn idx(self: *const Grid, x: u32, y: u32) u32 {
    return y * self.width + x;
}

pub fn xy(self: *const Grid, i: u32) struct { x: u32, y: u32 } {
    return .{ .x = i % self.width, .y = i / self.width };
}

pub fn inBounds(self: *const Grid, x: u32, y: u32) bool {
    return x < self.width and y < self.height;
}

/// Coord-based (nice for editing/debug)
pub fn isBlocked(self: *const Grid, x: u32, y: u32) bool {
    return self.blocked[self.idx(x, y)];
}

/// Index-based (what A* wants)
pub fn isBlockedIdx(self: *const Grid, i: u32) bool {
    return self.blocked[@as(usize, i)];
}

pub fn setBlocked(self: *Grid, x: u32, y: u32, v: bool) void {
    self.blocked[self.idx(x, y)] = v;
}

pub fn setBlockedIdx(self: *Grid, i: u32, v: bool) void {
    self.blocked[@as(usize, i)] = v;
}

/// world -> cell
pub fn worldToCell(self: *const Grid, wx: f32, wy: f32) ?Cell {
    const fx = (wx - self.origin_x) / self.cell_size;
    const fy = (wy - self.origin_y) / self.cell_size;
    if (fx < 0 or fy < 0) return null;

    const x: u32 = @intFromFloat(fx);
    const y: u32 = @intFromFloat(fy);
    if (!self.inBounds(x, y)) return null;
    return .{ .x = x, .y = y };
}

pub fn cellCenter(self: *const Grid, x: u32, y: u32) Point {
    return .{
        .x = self.origin_x + (@as(f32, @floatFromInt(x)) + 0.5) * self.cell_size,
        .y = self.origin_y + (@as(f32, @floatFromInt(y)) + 0.5) * self.cell_size,
    };
}

/// Scene helper: mark every cell overlapped by an axis-aligned rect (world coords) as blocked/unblocked.
/// This is one common way to "bake" collision geometry into the nav grid.
pub fn markRect(self: *Grid, x: f32, y: f32, w: f32, h: f32, v: bool) void {
    // Convert world rect to cell range.
    const min_fx = (x - self.origin_x) / self.cell_size;
    const min_fy = (y - self.origin_y) / self.cell_size;
    const max_fx = (x + w - self.origin_x) / self.cell_size;
    const max_fy = (y + h - self.origin_y) / self.cell_size;

    var min_x: i32 = @intFromFloat(@floor(min_fx));
    var min_y: i32 = @intFromFloat(@floor(min_fy));
    var max_x: i32 = @intFromFloat(@floor(max_fx));
    var max_y: i32 = @intFromFloat(@floor(max_fy));

    // Clamp to grid bounds.
    if (min_x < 0) min_x = 0;
    if (min_y < 0) min_y = 0;
    const w_i32: i32 = @intCast(self.width);
    const h_i32: i32 = @intCast(self.height);
    if (max_x >= w_i32) max_x = w_i32 - 1;
    if (max_y >= h_i32) max_y = h_i32 - 1;

    var yy: i32 = min_y;
    while (yy <= max_y) : (yy += 1) {
        var xx: i32 = min_x;
        while (xx <= max_x) : (xx += 1) {
            self.setBlocked(@intCast(xx), @intCast(yy), v);
        }
    }
}

pub fn tryNeighbor4(self: *const Grid, i: u32, dir: u2) ?u32 {
    const c = self.xy(i);
    const d: Dir = @enumFromInt(dir);

    // First check if movement is blocked by an edge (if edges are enabled)
    if (self.isEdgeBlocked(c.x, c.y, d)) return null;

    // Then check bounds
    return switch (d) {
        .west => if (c.x > 0) self.idx(c.x - 1, c.y) else null,
        .east => if (c.x + 1 < self.width) self.idx(c.x + 1, c.y) else null,
        .north => if (c.y > 0) self.idx(c.x, c.y - 1) else null,
        .south => if (c.y + 1 < self.height) self.idx(c.x, c.y + 1) else null,
    };
}

// ============================================================================
// Edge-based blocking (for mazes/thin walls)
// ============================================================================

/// Check if there's a wall blocking movement from cell (x,y) in direction dir
pub fn isEdgeBlocked(self: *const Grid, x: u32, y: u32, dir: Dir) bool {
    return switch (dir) {
        .north => self.hasWallNorth(x, y),
        .south => self.hasWallSouth(x, y),
        .west => self.hasWallWest(x, y),
        .east => self.hasWallEast(x, y),
    };
}

/// Set wall on north edge of cell (x, y)
pub fn setWallNorth(self: *Grid, x: u32, y: u32, blocked: bool) void {
    if (self.edges_h) |edges| {
        edges[@as(usize, y) * @as(usize, self.width) + @as(usize, x)] = blocked;
    }
}

/// Set wall on south edge of cell (x, y)
pub fn setWallSouth(self: *Grid, x: u32, y: u32, blocked: bool) void {
    if (self.edges_h) |edges| {
        edges[@as(usize, y + 1) * @as(usize, self.width) + @as(usize, x)] = blocked;
    }
}

/// Set wall on west edge of cell (x, y)
pub fn setWallWest(self: *Grid, x: u32, y: u32, blocked: bool) void {
    if (self.edges_v) |edges| {
        edges[@as(usize, y) * (@as(usize, self.width) + 1) + @as(usize, x)] = blocked;
    }
}

/// Set wall on east edge of cell (x, y)
pub fn setWallEast(self: *Grid, x: u32, y: u32, blocked: bool) void {
    if (self.edges_v) |edges| {
        edges[@as(usize, y) * (@as(usize, self.width) + 1) + @as(usize, x) + 1] = blocked;
    }
}

/// Check wall on north edge of cell (x, y)
pub fn hasWallNorth(self: *const Grid, x: u32, y: u32) bool {
    const edges = self.edges_h orelse return false;
    return edges[@as(usize, y) * @as(usize, self.width) + @as(usize, x)];
}

/// Check wall on south edge of cell (x, y)
pub fn hasWallSouth(self: *const Grid, x: u32, y: u32) bool {
    const edges = self.edges_h orelse return false;
    return edges[@as(usize, y + 1) * @as(usize, self.width) + @as(usize, x)];
}

/// Check wall on west edge of cell (x, y)
pub fn hasWallWest(self: *const Grid, x: u32, y: u32) bool {
    const edges = self.edges_v orelse return false;
    return edges[@as(usize, y) * (@as(usize, self.width) + 1) + @as(usize, x)];
}

/// Check wall on east edge of cell (x, y)
pub fn hasWallEast(self: *const Grid, x: u32, y: u32) bool {
    const edges = self.edges_v orelse return false;
    return edges[@as(usize, y) * (@as(usize, self.width) + 1) + @as(usize, x) + 1];
}

/// Set all four walls for a cell (convenience for maze building)
pub fn setWalls(self: *Grid, x: u32, y: u32, n: bool, e: bool, s: bool, w: bool) void {
    self.setWallNorth(x, y, n);
    self.setWallEast(x, y, e);
    self.setWallSouth(x, y, s);
    self.setWallWest(x, y, w);
}
