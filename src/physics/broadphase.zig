const std = @import("std");
const Allocator = std.mem.Allocator;
const Body = @import("Body.zig");
const Aabb = @import("../math/Aabb.zig");

pub const CollisionPair = struct {
    a: *Body,
    b: *Body,
};

pub const SpatialHash = struct {
    cell_size: f32,
    inv_cell_size: f32,

    // The Grid: Maps "Cell Hash" -> "List of Bodies in that cell", each body
    // as its index into `bodies` and `bounds`.
    cells: std.AutoHashMap(u64, std.ArrayList(u32)),

    // Every body placed by the latest update and its bounds, worked out once
    // per body. A body is in several cells and is compared with everything
    // else in each of them, so asking it for its bounds each time would redo
    // the same trigonometry dozens of times a step.
    bodies: std.ArrayList(*Body) = .empty,
    bounds: std.ArrayList(Aabb) = .empty,

    // The Cache: A linear list of unique pairs found this frame
    pairs: std.ArrayList(CollisionPair),

    // Cells that held at least one body in the latest update.
    used_cells: usize = 0,
    // Scratch list of cell keys to drop while pruning.
    stale_keys: std.ArrayList(u64) = .empty,

    alloc: Allocator,

    pub fn init(alloc: Allocator, cell_size: f32) SpatialHash {
        return .{
            .cell_size = cell_size,
            .inv_cell_size = 1.0 / cell_size,
            .cells = std.AutoHashMap(u64, std.ArrayList(u32)).init(alloc),
            .pairs = .empty,
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *SpatialHash) void {
        var it = self.cells.valueIterator();
        while (it.next()) |list| {
            list.deinit(self.alloc);
        }
        self.cells.deinit();
        self.bodies.deinit(self.alloc);
        self.bounds.deinit(self.alloc);
        self.pairs.deinit(self.alloc);
        self.stale_keys.deinit(self.alloc);
    }

    fn hashCoords(x: i32, y: i32) u64 {
        const ux: u32 = @bitCast(x);
        const uy: u32 = @bitCast(y);
        return (@as(u64, ux) << 32) | @as(u64, uy);
    }

    fn getCellCoord(self: *const SpatialHash, val: f32) i32 {
        // Clamp far-away bodies into a range where the conversion is defined and
        // the cell loops below cannot overflow.
        const limit: f32 = 1 << 30;
        return @intFromFloat(std.math.clamp(@floor(val * self.inv_cell_size), -limit, limit));
    }

    /// Frees cells nothing touched in the previous update once they clearly
    /// outnumber the live ones, so the map follows where bodies are now rather
    /// than everywhere they have ever been. The slack avoids reallocating the
    /// lists of cells that bodies move in and out of every step.
    fn pruneUnusedCells(self: *SpatialHash) !void {
        if (self.cells.count() <= self.used_cells * 2 + 256) return;

        self.stale_keys.clearRetainingCapacity();
        var it = self.cells.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.items.len == 0) try self.stale_keys.append(self.alloc, entry.key_ptr.*);
        }
        for (self.stale_keys.items) |key| {
            if (self.cells.fetchRemove(key)) |removed| {
                var list = removed.value;
                list.deinit(self.alloc);
            }
        }
    }

    /// Rebuilds collision pairs from a copyable iterator with next() ?*Body.
    pub fn update(self: *SpatialHash, bodies: anytype) !void {
        try self.pruneUnusedCells();
        var it = self.cells.valueIterator();
        while (it.next()) |list| list.clearRetainingCapacity();
        self.pairs.clearRetainingCapacity();
        self.bodies.clearRetainingCapacity();
        self.bounds.clearRetainingCapacity();
        self.used_cells = 0;

        var body_iter = bodies;
        while (body_iter.next()) |body| {
            const aabb = body.aabb();
            // A body whose position has become NaN or infinite cannot be placed.
            if (!std.math.isFinite(aabb.min.x) or !std.math.isFinite(aabb.min.y) or
                !std.math.isFinite(aabb.max.x) or !std.math.isFinite(aabb.max.y)) continue;
            const min_x = self.getCellCoord(aabb.min.x);
            const max_x = self.getCellCoord(aabb.max.x);
            const min_y = self.getCellCoord(aabb.min.y);
            const max_y = self.getCellCoord(aabb.max.y);

            const index: u32 = @intCast(self.bodies.items.len);
            try self.bodies.append(self.alloc, body);
            try self.bounds.append(self.alloc, aabb);

            var y = min_y;
            while (y <= max_y) : (y += 1) {
                var x = min_x;
                while (x <= max_x) : (x += 1) {
                    const key = hashCoords(x, y);
                    const res = try self.cells.getOrPut(key);
                    if (!res.found_existing) {
                        res.value_ptr.* = .empty;
                    }
                    if (res.value_ptr.items.len == 0) self.used_cells += 1;
                    try res.value_ptr.append(self.alloc, index);
                }
            }
        }

        try self.collectPairs();
    }

    /// Two bodies whose bounds overlap usually share several cells. Each pair
    /// is reported from exactly one of them: the cell holding the minimum corner
    /// of the overlap of their bounds, which both bodies are registered in. That
    /// is exact and needs no set of already-seen pairs.
    fn collectPairs(self: *SpatialHash) !void {
        var cell_it = self.cells.iterator();
        while (cell_it.next()) |entry| {
            const items = entry.value_ptr.items;
            if (items.len < 2) continue;
            const cell_key = entry.key_ptr.*;

            for (items, 0..) |index1, i| {
                const bounds1 = self.bounds.items[index1];
                for (items[i + 1 ..]) |index2| {
                    // Bounds first: they sit together in one array, while the
                    // bodies are spread through the world's storage.
                    const bounds2 = self.bounds.items[index2];
                    if (!bounds1.intersects(bounds2)) continue;
                    const b1 = self.bodies.items[index1];
                    const b2 = self.bodies.items[index2];
                    if (b1.kind != .dynamic and b2.kind != .dynamic) continue;

                    const owner_cell = hashCoords(
                        self.getCellCoord(@max(bounds1.min.x, bounds2.min.x)),
                        self.getCellCoord(@max(bounds1.min.y, bounds2.min.y)),
                    );
                    if (owner_cell != cell_key) continue;

                    try self.pairs.append(self.alloc, .{ .a = b1, .b = b2 });
                }
            }
        }
    }
};

const TestBodies = struct {
    items: []Body,
    index: usize = 0,

    pub fn next(self: *TestBodies) ?*Body {
        if (self.index >= self.items.len) return null;
        defer self.index += 1;
        return &self.items[self.index];
    }
};

test "cells a body has left are released instead of accumulating" {
    const Vec2 = @import("../math/Vec2.zig");
    const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
    var hash = SpatialHash.init(std.testing.allocator, 64);
    defer hash.deinit();
    var bodies = [_]Body{Body.initDynamic(PhysicsShape.circ(4), Vec2.zero, .{})};
    for (0..5000) |i| {
        bodies[0].position = Vec2.init(@as(f32, @floatFromInt(i)) * 64 + 32, 32);
        try hash.update(TestBodies{ .items = &bodies });
    }
    try std.testing.expect(hash.cells.count() < 1000);
    try std.testing.expectEqual(@as(usize, 1), hash.used_cells);
}

test "bodies at non-finite or enormous positions do not crash the broadphase" {
    const Vec2 = @import("../math/Vec2.zig");
    const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
    var hash = SpatialHash.init(std.testing.allocator, 64);
    defer hash.deinit();
    var bodies = [_]Body{
        Body.initDynamic(PhysicsShape.circ(4), Vec2.init(std.math.nan(f32), 0), .{}),
        Body.initDynamic(PhysicsShape.circ(4), Vec2.init(std.math.inf(f32), 0), .{}),
        Body.initDynamic(PhysicsShape.circ(4), Vec2.init(1e30, -1e30), .{}),
        Body.initDynamic(PhysicsShape.circ(4), Vec2.zero, .{}),
        Body.initStatic(PhysicsShape.circ(4), Vec2.init(2, 0), .{}),
    };
    try hash.update(TestBodies{ .items = &bodies });
    try std.testing.expectEqual(@as(usize, 1), hash.pairs.items.len);
}

test "bodies sharing many cells are paired exactly once" {
    const Vec2 = @import("../math/Vec2.zig");
    const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
    var hash = SpatialHash.init(std.testing.allocator, 64);
    defer hash.deinit();
    var rng = std.Random.DefaultPrng.init(11);
    const random = rng.random();
    var bodies: [40]Body = undefined;
    for (&bodies) |*body| {
        const position = Vec2.init(random.float(f32) * 600 - 300, random.float(f32) * 600 - 300);
        body.* = Body.initDynamic(PhysicsShape.rect(40 + random.float(f32) * 300, 40 + random.float(f32) * 300), position, .{
            .rotation = random.float(f32) * 3,
        });
    }
    try hash.update(TestBodies{ .items = &bodies });

    // Compare against every overlapping pair found by brute force.
    var expected: usize = 0;
    for (&bodies, 0..) |*a, i| {
        for (bodies[i + 1 ..]) |*b| {
            if (!a.aabb().intersects(b.aabb())) continue;
            expected += 1;
            var found: usize = 0;
            for (hash.pairs.items) |pair| {
                if ((pair.a == a and pair.b == b) or (pair.a == b and pair.b == a)) found += 1;
            }
            try std.testing.expectEqual(@as(usize, 1), found);
        }
    }
    try std.testing.expect(expected > 100);
    try std.testing.expectEqual(expected, hash.pairs.items.len);
}

test "bounds are worked out once per body, however many cells and neighbours it has" {
    const Vec2 = @import("../math/Vec2.zig");
    const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;
    var hash = SpatialHash.init(std.testing.allocator, 64);
    defer hash.deinit();
    // Three overlapping rotated boxes, each spanning several cells, and one
    // body that cannot be placed.
    var bodies = [_]Body{
        Body.initDynamic(PhysicsShape.rect(150, 150), Vec2.init(0, 0), .{ .rotation = 0.4 }),
        Body.initDynamic(PhysicsShape.rect(150, 150), Vec2.init(60, 20), .{ .rotation = 1.1 }),
        Body.initStatic(PhysicsShape.rect(150, 150), Vec2.init(-40, 70), .{ .rotation = 2.0 }),
        Body.initDynamic(PhysicsShape.circ(4), Vec2.init(std.math.nan(f32), 0), .{}),
    };
    try hash.update(TestBodies{ .items = &bodies });
    try std.testing.expectEqual(@as(usize, 3), hash.bodies.items.len);
    try std.testing.expectEqual(@as(usize, 3), hash.bounds.items.len);
    for (hash.bodies.items, hash.bounds.items) |body, bounds| {
        try std.testing.expectEqual(body.aabb(), bounds);
    }
    try std.testing.expectEqual(@as(usize, 3), hash.pairs.items.len);

    // A second update starts again rather than adding to the first.
    try hash.update(TestBodies{ .items = bodies[0..2] });
    try std.testing.expectEqual(@as(usize, 2), hash.bodies.items.len);
    try std.testing.expectEqual(@as(usize, 1), hash.pairs.items.len);
}
