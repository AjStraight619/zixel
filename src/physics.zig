//! Physics simulation and collision APIs, independent of rendering.
pub const Physics = @import("physics/Physics.zig");
pub const Body = @import("physics/Body.zig");
pub const BodyKind = Body.BodyKind;
pub const BodyOptions = Body.BodyOptions;
pub const PhysicsShape = @import("math/shapes.zig").PhysicsShape;
pub const collision = @import("physics/collision.zig");
pub const response = @import("physics/response.zig");
pub const narrowphase = @import("physics/narrowphase.zig");
