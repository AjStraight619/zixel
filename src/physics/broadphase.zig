const std = @import("std");
const rl = @import("raylib");
const Body = @import("body.zig").Body;
const Vector2 = rl.Vector2;
const ArrayList = std.ArrayList;

/// Collision pair - two bodies that might be colliding
pub const CollisionPair = struct {
    body1: *Body,
    body2: *Body,

    pub fn init(body1: *Body, body2: *Body) CollisionPair {
        return CollisionPair{ .body1 = body1, .body2 = body2 };
    }
};

/// Spatial hash for broad phase collision detection
pub const SpatialHash = struct {
    /// Cell size for the spatial hash grid
    cell_size: f32,

    /// Hash map storing lists of bodies in each cell
    cells: std.HashMap(u64, ArrayList(*Body), std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),

    /// Allocator for dynamic arrays
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, cell_size: f32) SpatialHash {
        return SpatialHash{
            .cell_size = cell_size,
            .cells = std.HashMap(u64, ArrayList(*Body), std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SpatialHash) void {
        // Clean up all the ArrayLists
        var iterator = self.cells.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.cells.deinit();
    }

    /// Hash function to convert 2D grid coordinates to a single hash value
    fn hashCoords(x: i32, y: i32) u64 {
        // Simple hash combining x and y coordinates
        const ux = @as(u64, @bitCast(@as(i64, x)));
        const uy = @as(u64, @bitCast(@as(i64, y)));
        return ux ^ (uy << 32) ^ (uy >> 32);
    }

    /// Get grid coordinates for a world position
    fn getGridCoords(self: *const SpatialHash, pos: Vector2) struct { x: i32, y: i32 } {
        return .{
            .x = @intFromFloat(@floor(pos.x / self.cell_size)),
            .y = @intFromFloat(@floor(pos.y / self.cell_size)),
        };
    }

    /// Get AABB (bounding box) for a body
    fn getBodyAABB(body: *const Body) struct { min: Vector2, max: Vector2 } {
        const shape = body.getShape();
        const pos = body.getPosition();

        switch (shape) {
            .circle => |circle| {
                return .{
                    .min = Vector2{ .x = pos.x - circle.radius, .y = pos.y - circle.radius },
                    .max = Vector2{ .x = pos.x + circle.radius, .y = pos.y + circle.radius },
                };
            },
            .rectangle => |rect| {
                // For rotated rectangles, we need a conservative AABB
                // This could be optimized by calculating the exact rotated AABB
                const half_diagonal = @sqrt(rect.width * rect.width + rect.height * rect.height) / 2.0;
                return .{
                    .min = Vector2{ .x = pos.x - half_diagonal, .y = pos.y - half_diagonal },
                    .max = Vector2{ .x = pos.x + half_diagonal, .y = pos.y + half_diagonal },
                };
            },
        }
    }

    /// Clear all bodies from the spatial hash
    pub fn clear(self: *SpatialHash) void {
        var iterator = self.cells.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.clearRetainingCapacity();
        }
    }

    /// Insert a body into the spatial hash
    pub fn insert(self: *SpatialHash, body: *Body) !void {
        const aabb = getBodyAABB(body);

        // Get the grid range that this body overlaps
        const min_grid = self.getGridCoords(aabb.min);
        const max_grid = self.getGridCoords(aabb.max);

        // Insert into all overlapping cells
        var y = min_grid.y;
        while (y <= max_grid.y) : (y += 1) {
            var x = min_grid.x;
            while (x <= max_grid.x) : (x += 1) {
                const hash = hashCoords(x, y);

                // Get or create the cell's body list
                const result = try self.cells.getOrPut(hash);
                if (!result.found_existing) {
                    result.value_ptr.* = ArrayList(*Body).init(self.allocator);
                }

                // Add body to this cell
                try result.value_ptr.append(body);
            }
        }
    }

    /// Find all potential collision pairs using the spatial hash
    pub fn findCollisionPairs(self: *SpatialHash, potential_pairs: *ArrayList(CollisionPair)) !void {
        potential_pairs.clearRetainingCapacity();

        // Use a set to avoid duplicate pairs
        var seen_pairs = std.HashMap(u64, void, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(self.allocator);
        defer seen_pairs.deinit();

        // Check each cell for internal collisions
        var iterator = self.cells.iterator();
        while (iterator.next()) |entry| {
            const bodies = entry.value_ptr;

            // Check all pairs within this cell
            for (bodies.items, 0..) |body1, i| {
                for (bodies.items[i + 1 ..]) |body2| {
                    // Create a unique pair ID (smaller ID first)
                    const id1 = body1.id;
                    const id2 = body2.id;
                    const pair_id = if (id1 < id2)
                        ((@as(u64, id1) << 32) | id2)
                    else
                        ((@as(u64, id2) << 32) | id1);

                    // Only add if we haven't seen this pair before
                    if (!seen_pairs.contains(pair_id)) {
                        try seen_pairs.put(pair_id, {});
                        try potential_pairs.append(CollisionPair.init(body1, body2));
                    }
                }
            }
        }
    }

    /// Query for bodies near a specific position
    pub fn query(self: *SpatialHash, position: Vector2, radius: f32, results: *ArrayList(*Body)) !void {
        results.clearRetainingCapacity();

        // Get the grid range to search
        const min_pos = Vector2{ .x = position.x - radius, .y = position.y - radius };
        const max_pos = Vector2{ .x = position.x + radius, .y = position.y + radius };
        const min_grid = self.getGridCoords(min_pos);
        const max_grid = self.getGridCoords(max_pos);

        // Use a set to avoid duplicates (bodies can be in multiple cells)
        var seen_bodies = std.HashMap(usize, void, std.hash_map.AutoContext(usize), std.hash_map.default_max_load_percentage).init(self.allocator);
        defer seen_bodies.deinit();

        // Search all overlapping cells
        var y = min_grid.y;
        while (y <= max_grid.y) : (y += 1) {
            var x = min_grid.x;
            while (x <= max_grid.x) : (x += 1) {
                const hash = hashCoords(x, y);

                if (self.cells.get(hash)) |bodies| {
                    for (bodies.items) |body| {
                        if (!seen_bodies.contains(body.id)) {
                            try seen_bodies.put(body.id, {});
                            try results.append(body);
                        }
                    }
                }
            }
        }
    }

    /// Get statistics about the spatial hash performance
    pub fn getStats(self: *const SpatialHash) struct { num_cells: usize, total_bodies: usize, max_bodies_per_cell: usize, avg_bodies_per_cell: f32 } {
        var total_bodies: usize = 0;
        var max_bodies: usize = 0;

        var iterator = self.cells.iterator();
        while (iterator.next()) |entry| {
            const count = entry.value_ptr.items.len;
            total_bodies += count;
            max_bodies = @max(max_bodies, count);
        }

        const num_cells = self.cells.count();
        const avg_bodies = if (num_cells > 0) @as(f32, @floatFromInt(total_bodies)) / @as(f32, @floatFromInt(num_cells)) else 0.0;

        return .{
            .num_cells = num_cells,
            .total_bodies = total_bodies,
            .max_bodies_per_cell = max_bodies,
            .avg_bodies_per_cell = avg_bodies,
        };
    }
};

/// Simple broad phase using AABB overlap test (for comparison/fallback)
pub const SimpleBroadPhase = struct {
    /// Find all collision pairs using brute force O(n²) method
    pub fn findCollisionPairs(bodies: []const *Body, potential_pairs: *ArrayList(CollisionPair)) !void {
        potential_pairs.clearRetainingCapacity();

        for (bodies, 0..) |body1, i| {
            for (bodies[i + 1 ..]) |body2| {
                // Simple AABB overlap test
                const aabb1 = SpatialHash.getBodyAABB(body1);
                const aabb2 = SpatialHash.getBodyAABB(body2);

                // Check if AABBs overlap
                if (aabb1.max.x >= aabb2.min.x and aabb1.min.x <= aabb2.max.x and
                    aabb1.max.y >= aabb2.min.y and aabb1.min.y <= aabb2.max.y)
                {
                    try potential_pairs.append(CollisionPair.init(body1, body2));
                }
            }
        }
    }
};
