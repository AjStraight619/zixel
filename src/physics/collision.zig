const std = @import("std");
const rl = @import("raylib");
const Body = @import("body.zig").Body;
const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;

// Import the new modules
const narrowphase = @import("narrowphase.zig");
const broadphase = @import("broadphase.zig");
const response = @import("response.zig");

// Re-export important types for convenience
pub const ContactManifold = narrowphase.ContactManifold;
pub const CollisionPair = broadphase.CollisionPair;
pub const SpatialHash = broadphase.SpatialHash;
pub const SimpleBroadPhase = broadphase.SimpleBroadPhase;
pub const NarrowPhase = narrowphase.NarrowPhase;
pub const CollisionResponse = response.CollisionResponse;

const Vector2 = rl.Vector2;
const ArrayList = std.ArrayList;

/// Main collision detection system that combines broad phase and narrow phase
pub const CollisionSystem = struct {
    /// Spatial hash for broad phase collision detection
    spatial_hash: SpatialHash,

    /// List to store potential collision pairs from broad phase
    potential_pairs: ArrayList(CollisionPair),

    /// List to store actual collisions found in narrow phase
    actual_collisions: ArrayList(ContactManifold),

    /// Physics settings
    restitution: f32 = 0.8,
    position_correction: f32 = 0.8,

    /// Performance stats
    last_broad_phase_pairs: usize = 0,
    last_narrow_phase_collisions: usize = 0,

    pub fn init(allocator: std.mem.Allocator, cell_size: f32) CollisionSystem {
        return CollisionSystem{
            .spatial_hash = SpatialHash.init(allocator, cell_size),
            .potential_pairs = ArrayList(CollisionPair).init(allocator),
            .actual_collisions = ArrayList(ContactManifold).init(allocator),
        };
    }

    pub fn deinit(self: *CollisionSystem) void {
        self.spatial_hash.deinit();
        self.potential_pairs.deinit();
        self.actual_collisions.deinit();
    }

    /// Update collision detection and response for all bodies
    pub fn update(self: *CollisionSystem, bodies: []const *Body) !void {
        // Clear previous frame data
        self.spatial_hash.clear();

        // Broad phase: Insert all bodies into spatial hash
        for (bodies) |body| {
            try self.spatial_hash.insert(body);
        }

        // Broad phase: Find potential collision pairs
        try self.spatial_hash.findCollisionPairs(&self.potential_pairs);
        self.last_broad_phase_pairs = self.potential_pairs.items.len;

        // Narrow phase: Test actual collisions
        self.actual_collisions.clearRetainingCapacity();
        for (self.potential_pairs.items) |pair| {
            if (NarrowPhase.checkBodiesCollision(pair.body1, pair.body2)) |manifold| {
                try self.actual_collisions.append(manifold);
            }
        }
        self.last_narrow_phase_collisions = self.actual_collisions.items.len;

        // Collision response: Resolve all collisions
        for (self.actual_collisions.items) |manifold| {
            // Find the bodies involved
            var body1: ?*Body = null;
            var body2: ?*Body = null;

            for (bodies) |body| {
                if (body.id == manifold.body1_id) body1 = body;
                if (body.id == manifold.body2_id) body2 = body;
            }

            if (body1 != null and body2 != null) {
                // Resolve collision with impulse
                CollisionResponse.resolveCollision(body1.?, body2.?, manifold, self.restitution);

                // Correct positions to prevent sinking
                CollisionResponse.correctPositions(body1.?, body2.?, manifold, self.position_correction);
            }
        }
    }

    /// Update using simple O(n²) broad phase (for comparison or small number of bodies)
    pub fn updateSimple(self: *CollisionSystem, bodies: []const *Body) !void {
        // Simple broad phase: Find potential collision pairs
        try SimpleBroadPhase.findCollisionPairs(bodies, &self.potential_pairs);
        self.last_broad_phase_pairs = self.potential_pairs.items.len;

        // Narrow phase: Test actual collisions
        self.actual_collisions.clearRetainingCapacity();
        for (self.potential_pairs.items) |pair| {
            if (NarrowPhase.checkBodiesCollision(pair.body1, pair.body2)) |manifold| {
                try self.actual_collisions.append(manifold);
            }
        }
        self.last_narrow_phase_collisions = self.actual_collisions.items.len;

        // Collision response: Resolve all collisions
        for (self.actual_collisions.items) |manifold| {
            // Find the bodies involved
            var body1: ?*Body = null;
            var body2: ?*Body = null;

            for (bodies) |body| {
                if (body.id == manifold.body1_id) body1 = body;
                if (body.id == manifold.body2_id) body2 = body;
            }

            if (body1 != null and body2 != null) {
                // Resolve collision with impulse
                CollisionResponse.resolveCollision(body1.?, body2.?, manifold, self.restitution);

                // Correct positions to prevent sinking
                CollisionResponse.correctPositions(body1.?, body2.?, manifold, self.position_correction);
            }
        }
    }

    /// Query for bodies near a specific position
    pub fn queryBodiesNear(self: *CollisionSystem, position: Vector2, radius: f32, results: *ArrayList(*Body)) !void {
        try self.spatial_hash.query(position, radius, results);
    }

    /// Get performance statistics
    pub fn getStats(self: *const CollisionSystem) struct {
        broad_phase_pairs: usize,
        narrow_phase_collisions: usize,
        spatial_hash_stats: @TypeOf(SpatialHash.getStats(@as(*const SpatialHash, undefined))),
    } {
        return .{
            .broad_phase_pairs = self.last_broad_phase_pairs,
            .narrow_phase_collisions = self.last_narrow_phase_collisions,
            .spatial_hash_stats = self.spatial_hash.getStats(),
        };
    }

    /// Set physics parameters
    pub fn setPhysicsParams(self: *CollisionSystem, restitution: f32, position_correction: f32) void {
        self.restitution = restitution;
        self.position_correction = position_correction;
    }
};

// Legacy compatibility functions for existing code
pub fn checkBodiesCollision(body1: *const Body, body2: *const Body) ?ContactManifold {
    return NarrowPhase.checkBodiesCollision(body1, body2);
}

pub fn checkShapesCollision(shape1: PhysicsShape, pos1: Vector2, rot1: f32, id1: usize, shape2: PhysicsShape, pos2: Vector2, rot2: f32, id2: usize) ?ContactManifold {
    return NarrowPhase.checkShapesCollision(shape1, pos1, rot1, id1, shape2, pos2, rot2, id2);
}

pub fn resolveCollision(body1: *Body, body2: *Body, manifold: ContactManifold, restitution: f32) void {
    return CollisionResponse.resolveCollision(body1, body2, manifold, restitution);
}

pub fn correctPositions(body1: *Body, body2: *Body, manifold: ContactManifold, correction_factor: f32) void {
    return CollisionResponse.correctPositions(body1, body2, manifold, correction_factor);
}
