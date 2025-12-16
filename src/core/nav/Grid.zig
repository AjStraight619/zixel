const std = @import("std");
const time = std.time;
const Allocator = std.mem.Allocator;

/// Scene-owned navigation grid.
/// Stores only static-ish level data: which cells are blocked.
/// No A* state lives here.
pub const Grid = @This();

width: u32,
height: u32,

cell_size: f32,
origin_x: f32 = 0,
origin_y: f32 = 0,

blocked: []bool, // len = width*height

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
    };
}

pub fn deinit(self: *Grid, alloc: Allocator) void {
    alloc.free(self.blocked);
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
pub fn worldToCell(self: *const Grid, wx: f32, wy: f32) ?struct { x: u32, y: u32 } {
    const fx = (wx - self.origin_x) / self.cell_size;
    const fy = (wy - self.origin_y) / self.cell_size;
    if (fx < 0 or fy < 0) return null;

    const x: u32 = @intFromFloat(fx);
    const y: u32 = @intFromFloat(fy);
    if (!self.inBounds(x, y)) return null;
    return .{ .x = x, .y = y };
}

pub fn cellCenter(self: *const Grid, x: u32, y: u32) struct { x: f32, y: f32 } {
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
    // dir: 0=left,1=right,2=up,3=down
    const c = self.xy(i);

    return switch (dir) {
        0 => if (c.x > 0) self.idx(c.x - 1, c.y) else null,
        1 => if (c.x + 1 < self.width) self.idx(c.x + 1, c.y) else null,
        2 => if (c.y > 0) self.idx(c.x, c.y - 1) else null,
        3 => if (c.y + 1 < self.height) self.idx(c.x, c.y + 1) else null,
    };
}
