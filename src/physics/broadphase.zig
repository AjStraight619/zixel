const std = @import("std");
const Allocator = std.mem.Allocator;
const Body = @import("Body.zig");
const EntitySlot = @import("../engine/EntitySlot.zig");

/// Unique key for deduplicating pairs
const PairKey = struct {
    a: usize,
    b: usize,

    fn init(b1: *Body, b2: *Body) PairKey {
        const i_1 = @intFromPtr(b1);
        const i_2 = @intFromPtr(b2);
        // Sort to ensure A-B is same as B-A
        if (i_1 < i_2) return .{ .a = i_1, .b = i_2 };
        return .{ .a = i_2, .b = i_1 };
    }
};

pub const CollisionPair = struct {
    a: *Body,
    b: *Body,
};

pub const SpatialHash = struct {
    cell_size: f32,
    inv_cell_size: f32,

    // The Grid: Maps "Cell Hash" -> "List of Bodies in that cell"
    cells: std.AutoHashMap(u64, std.ArrayList(*Body)),

    // The Cache: A linear list of unique pairs found this frame
    pairs: std.ArrayList(CollisionPair),

    // Helper to ensure we don't add the same pair twice
    pair_set: std.AutoHashMap(u64, void),

    alloc: Allocator,

    pub fn init(alloc: Allocator, cell_size: f32) SpatialHash {
        return .{
            .cell_size = cell_size,
            .inv_cell_size = 1.0 / cell_size,
            .cells = std.AutoHashMap(u64, std.ArrayList(*Body)).init(alloc),
            .pairs = .empty,
            .pair_set = std.AutoHashMap(u64, void).init(alloc),
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *SpatialHash) void {
        var it = self.cells.valueIterator();
        while (it.next()) |list| {
            list.deinit(self.alloc);
        }
        self.cells.deinit();
        self.pairs.deinit(self.alloc);
        self.pair_set.deinit();
    }

    fn hashCoords(x: i32, y: i32) u64 {
        const ux: u32 = @bitCast(x);
        const uy: u32 = @bitCast(y);
        return (@as(u64, ux) << 32) | @as(u64, uy);
    }

    fn getCellCoord(self: *const SpatialHash, val: f32) i32 {
        return @intFromFloat(@floor(val * self.inv_cell_size));
    }

    /// Rebuilds the grid and collects all unique collision pairs from EntitySlots.
    /// Alias: update
    pub fn updateFromEntities(self: *SpatialHash, slots: []EntitySlot) !void {
        var it = self.cells.valueIterator();
        while (it.next()) |list| list.clearRetainingCapacity();
        self.pairs.clearRetainingCapacity();
        self.pair_set.clearRetainingCapacity();

        for (slots) |*slot| {
            if (!slot.alive) continue;
            const body = &slot.entity.body;

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
                    const res = try self.cells.getOrPut(key);
                    if (!res.found_existing) {
                        res.value_ptr.* = .empty;
                    }
                    try res.value_ptr.append(self.alloc, body);
                }
            }
        }

        self.collectPairs();
    }

    fn collectPairs(self: *SpatialHash) void {
        var cell_it = self.cells.valueIterator();
        while (cell_it.next()) |list| {
            const items = list.items;
            if (items.len < 2) continue;

            for (items, 0..) |b1, i| {
                for (items[i + 1 ..]) |b2| {
                    if (b1.kind != .dynamic and b2.kind != .dynamic) continue;
                    if (!b1.aabb().intersects(b2.aabb())) continue;

                    const pair_key = PairKey.init(b1, b2);
                    const k = @as(u64, pair_key.a) +% (@as(u64, pair_key.b) *% 0x9e3779b97f4a7c15);

                    const res = self.pair_set.getOrPut(k) catch continue;
                    if (!res.found_existing) {
                        self.pairs.append(self.alloc, .{ .a = b1, .b = b2 }) catch continue;
                    }
                }
            }
        }
    }
};
