//! Collision detection and response system
//! Re-exports all collision-related types for convenience

const narrowphase = @import("narrowphase.zig");
const broadphase = @import("broadphase.zig");
pub const response = @import("response.zig");

// Re-export important types
pub const ContactManifold = narrowphase.ContactManifold;
pub const narrow_phase = narrowphase;
pub const CollisionPair = broadphase.CollisionPair;
pub const SpatialHash = broadphase.SpatialHash;

// Convenience functions
pub const checkBodiesCollision = narrowphase.checkBodiesCollision;
pub const resolveWithMaterials = response.resolveWithMaterials;
pub const correctPositions = response.correctPositions;
