//! Shared entity storage layout used by the world and broadphase.
const Entity = @import("Entity.zig").Entity;

entity: Entity,
generation: u32 = 1,
alive: bool = false,
