// Ensure all tests are compiled
comptime {
    _ = @import("engine/engine.zig");
    _ = @import("physics/collision.zig");
    _ = @import("physics/narrowphase.zig");
    _ = @import("physics/broadphase.zig");
    _ = @import("physics/response.zig");
    _ = @import("physics/world.zig");
    _ = @import("physics/body.zig");
    _ = @import("input/keybinds.zig");
    _ = @import("math/shapes.zig");
    _ = @import("math/aabb.zig");
    _ = @import("graphics/window.zig");
    _ = @import("graphics/config.zig");
    _ = @import("physics/config.zig");
}
