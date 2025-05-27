const rl = @import("raylib");
const Vector2 = rl.Vector2;

pub const PhysicsConfig = struct {
    gravity: Vector2 = Vector2{ .x = 0, .y = -9.81 },
    // Add other physics-related configurations here
    // For example:
    // iterations: u32 = 10, // Number of solver iterations
    // time_step: f32 = 1.0 / 60.0, // Fixed time step for physics updates
};
