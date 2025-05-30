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
    _ = @import("core/math/shapes.zig");
    _ = @import("core/math/aabb.zig");
    _ = @import("renderer/window.zig");
    _ = @import("renderer/config.zig");
    _ = @import("physics/config.zig");
}
