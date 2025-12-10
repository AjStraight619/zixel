//! Collision detection and response system
//! Re-exports all collision-related types for convenience

const narrowphase = @import("narrowphase.zig");
const broadphase = @import("broadphase.zig");
const response = @import("response.zig");

// Re-export important types
pub const ContactManifold = narrowphase.ContactManifold;
pub const NarrowPhase = narrowphase.NarrowPhase;
pub const CollisionPair = broadphase.CollisionPair;
pub const SpatialHash = broadphase.SpatialHash;
pub const SimpleBroadPhase = broadphase.SimpleBroadPhase;
pub const CollisionResponse = response.CollisionResponse;

// Convenience functions
pub fn checkBodiesCollision(body1: anytype, body2: anytype) ?ContactManifold {
    return NarrowPhase.checkBodiesCollision(body1, body2);
}

pub fn resolveCollision(body1: anytype, body2: anytype, manifold: ContactManifold, restitution: f32, threshold: f32) void {
    return CollisionResponse.resolveCollision(body1, body2, manifold, restitution, threshold);
}

pub fn correctPositions(body1: anytype, body2: anytype, manifold: ContactManifold, correction_factor: f32) void {
    return CollisionResponse.correctPositions(body1, body2, manifold, correction_factor);
}
