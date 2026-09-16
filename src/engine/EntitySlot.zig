//! Shared entity storage layout used by the world and broadphase.
const Entity = @import("Entity.zig");

entity: Entity,
generation: u32 = 1,
alive: bool = false,
