const std = @import("std");
const Vec2 = @import("../math/vec2.zig");
const Body = @import("body.zig").Body;
const Allocator = std.mem.Allocator;

/// Spatial hash grid for O(n) broadphase collision detection
pub const SpatialHash = struct {
    cell_size: f32,
    inv_cell_size: f32,
    cells: std.AutoHashMap(u64, std.ArrayList(*Body)),
    alloc: Allocator,

    pub fn init(alloc: Allocator, cell_size: f32) SpatialHash {
        return .{
            .cell_size = cell_size,
            .inv_cell_size = 1.0 / cell_size,
            .cells = std.AutoHashMap(u64, std.ArrayList(*Body)).init(alloc),
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *SpatialHash) void {
        var it = self.cells.valueIterator();
        while (it.next()) |list| {
            var mutable_list = list.*;
            mutable_list.deinit(self.alloc);
        }
        self.cells.deinit();
    }

    fn hashCoords(x: i32, y: i32) u64 {
        const ux: u32 = @bitCast(x);
        const uy: u32 = @bitCast(y);
        return (@as(u64, ux) << 32) | @as(u64, uy);
    }

    fn getCellCoord(self: *const SpatialHash, val: f32) i32 {
        return @intFromFloat(@floor(val * self.inv_cell_size));
    }

    /// Clear all bodies from the hash (call each frame before inserting)
    pub fn clear(self: *SpatialHash) void {
        var it = self.cells.valueIterator();
        while (it.next()) |list| {
            list.clearRetainingCapacity();
        }
    }

    /// Insert a body into all cells it overlaps
    pub fn insert(self: *SpatialHash, body: *Body) void {
        const aabb = body.aabb();

        const min_x = self.getCellCoord(aabb.min.x);
        const max_x = self.getCellCoord(aabb.max.x);
        const min_y = self.getCellCoord(aabb.min.y);
        const max_y = self.getCellCoord(aabb.max.y);

        var y = min_y;
        while (y <= max_y) : (y += 1) {
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const key = hashCoords(x, y);
                const result = self.cells.getOrPut(key) catch continue;
                if (!result.found_existing) {
                    result.value_ptr.* = .empty;
                }
                result.value_ptr.append(self.alloc, body) catch {};
            }
        }
    }

    /// Iterate over potential collision pairs (calls callback for each unique pair)
    pub fn forEachPair(self: *SpatialHash, context: anytype, callback: fn (@TypeOf(context), *Body, *Body) void) void {
        var cell_it = self.cells.valueIterator();
        while (cell_it.next()) |bodies| {
            const items = bodies.items;
            for (items, 0..) |body1, i| {
                for (items[i + 1 ..]) |body2| {
                    // Use pointer comparison to ensure unique pairs and consistent ordering
                    const p1 = @intFromPtr(body1);
                    const p2 = @intFromPtr(body2);
                    // Only process if body1 ptr < body2 ptr (avoids duplicates across cells)
                    if (p1 < p2) {
                        callback(context, body1, body2);
                    } else if (p2 < p1) {
                        callback(context, body2, body1);
                    }
                }
            }
        }
    }
};
