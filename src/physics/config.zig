const rl = @import("raylib");
const Vector2 = rl.Vector2;

pub const PhysicsConfig = struct {
    // World settings
    gravity: Vector2 = Vector2{ .x = 0, .y = 9.81 },

    // Solver settings
    position_iterations: u32 = 3, // Number of position correction iterations
    velocity_iterations: u32 = 8, // Number of velocity solver iterations

    // Timestep settings
    physics_time_step: f32 = 1.0 / 60.0, // Fixed physics timestep (60 FPS)
    max_delta_time: f32 = 1.0 / 30.0, // Maximum allowed delta time to prevent spiral of death

    // Collision settings
    allow_sleeping: bool = true, // Allow bodies to go to sleep when inactive
    sleep_time_threshold: f32 = 0.5, // Time before a body can sleep (seconds)
    sleep_velocity_threshold: f32 = 0.1, // Velocity threshold for sleeping

    // Contact settings
    contact_slop: f32 = 0.005, // Allowed penetration before position correction
    baumgarte_factor: f32 = 0.2, // Position correction factor (0-1)

    // Performance settings
    enable_warm_starting: bool = true, // Reuse impulses from previous frame
    enable_continuous_physics: bool = false, // Continuous collision detection (expensive)

    // Debug settings
    debug_draw_aabb: bool = false,
    debug_draw_contacts: bool = false,
    debug_draw_joints: bool = false,
};
