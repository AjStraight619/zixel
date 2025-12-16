const std = @import("std");
const Allocator = std.mem.Allocator;

const Grid = @import("Grid.zig").Grid;
const Astar = @import("astar.zig");

pub const Nav = struct {
    grid: Grid,
    scratch: Astar.Scratch,
    path: std.ArrayList(u32),

    pub const Config = struct {
        cell_size: f32 = 24,
        origin_x: f32 = 0,
        origin_y: f32 = 0,
        width: u32,
        height: u32,
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
        const path = std.ArrayList(u32).init(alloc);

        return .{ .grid = grid, .scratch = scratch, .path = path };
    }

    pub fn deinit(self: *Nav, alloc: Allocator) void {
        self.path.deinit();
        self.scratch.deinit(alloc);
        self.grid.deinit(alloc);
        self.* = undefined;
    }

    pub fn clear(self: *Nav) void {
        @memset(self.grid.blocked, false);
        self.path.clearRetainingCapacity();
    }

    /// High-level API: world coords -> start/goal indices
    pub fn worldToIdx(self: *const Nav, wx: f32, wy: f32) ?u32 {
        if (self.grid.worldToCell(wx, wy)) |c| {
            return self.grid.idx(c.x, c.y);
        }
        return null;
    }

    pub fn idxToWorldCenter(self: *const Nav, idx: u32) struct { x: f32, y: f32 } {
        const c = self.grid.xy(idx);
        return self.grid.cellCenter(c.x, c.y);
    }

    /// Find path (writes into self.path)
    pub fn findPathIdx(self: *Nav, start: u32, goal: u32) bool {
        return Astar.findPath(&self.grid, &self.scratch, start, goal, &self.path);
    }
};
