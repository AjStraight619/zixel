const std = @import("std");
const rl = @import("raylib");
const Vector2 = rl.Vector2;
const Rectangle = rl.Rectangle;

pub const CameraType = enum {
    fixed, // Static camera (menus, cutscenes)
    follow_player, // Smooth following (platformers)
    free_roam, // Player-controlled (strategy games)
    bounded, // Camera with world boundaries
    shake, // Temporary screen shake effect
};

pub const CameraBounds = struct {
    min_x: f32 = -std.math.inf(f32),
    max_x: f32 = std.math.inf(f32),
    min_y: f32 = -std.math.inf(f32),
    max_y: f32 = std.math.inf(f32),

    pub fn clamp(self: CameraBounds, pos: Vector2) Vector2 {
        return Vector2{
            .x = std.math.clamp(pos.x, self.min_x, self.max_x),
            .y = std.math.clamp(pos.y, self.min_y, self.max_y),
        };
    }
};

pub const CameraConfig = struct {
    camera_type: CameraType = .fixed,

    // Follow settings
    follow_speed: f32 = 2.0,
    follow_offset: Vector2 = Vector2{ .x = 0, .y = 0 },

    // Bounds
    bounds: ?CameraBounds = null,

    // Shake settings
    shake_intensity: f32 = 0.0,
    shake_duration: f32 = 0.0,

    // Zoom settings
    min_zoom: f32 = 0.1,
    max_zoom: f32 = 3.0,
    zoom_speed: f32 = 0.1,
};

pub const Camera = struct {
    camera2d: rl.Camera2D,
    config: CameraConfig,

    // Internal state
    target_position: Vector2,
    follow_target: ?Vector2 = null,
    shake_timer: f32 = 0.0,
    shake_offset: Vector2 = Vector2{ .x = 0, .y = 0 },

    const Self = @This();

    pub fn init(config: CameraConfig) Self {
        return Self{
            .camera2d = rl.Camera2D{
                .target = Vector2{ .x = 0, .y = 0 },
                .offset = Vector2{ .x = 400, .y = 300 }, // Screen center
                .rotation = 0.0,
                .zoom = 1.0,
            },
            .config = config,
            .target_position = Vector2{ .x = 0, .y = 0 },
        };
    }

    pub fn update(self: *Self, dt: f32) void {
        switch (self.config.camera_type) {
            .fixed => {
                // No movement - use dt to prevent unused parameter warning
            },
            .follow_player => {
                if (self.follow_target) |target| {
                    self.updateFollowCamera(target, dt);
                }
            },
            .free_roam => {
                self.updateFreeRoamCamera(dt);
            },
            .bounded => {
                if (self.follow_target) |target| {
                    self.updateFollowCamera(target, dt);
                }
                self.applyBounds();
            },
            .shake => {
                self.updateShakeCamera(dt);
            },
        }

        // Apply shake offset
        self.camera2d.target = Vector2{
            .x = self.target_position.x + self.shake_offset.x,
            .y = self.target_position.y + self.shake_offset.y,
        };
    }

    fn updateFollowCamera(self: *Self, target: Vector2, dt: f32) void {
        const desired_pos = Vector2{
            .x = target.x + self.config.follow_offset.x,
            .y = target.y + self.config.follow_offset.y,
        };

        // Smooth interpolation
        const lerp_factor = 1.0 - std.math.pow(f32, 0.5, self.config.follow_speed * dt);
        self.target_position = Vector2{
            .x = self.target_position.x + (desired_pos.x - self.target_position.x) * lerp_factor,
            .y = self.target_position.y + (desired_pos.y - self.target_position.y) * lerp_factor,
        };
    }

    fn updateFreeRoamCamera(self: *Self, dt: f32) void {
        const move_speed: f32 = 300.0 * dt / self.camera2d.zoom;

        if (rl.isKeyDown(.a)) self.target_position.x -= move_speed;
        if (rl.isKeyDown(.d)) self.target_position.x += move_speed;
        if (rl.isKeyDown(.w)) self.target_position.y -= move_speed;
        if (rl.isKeyDown(.s)) self.target_position.y += move_speed;

        // Zoom with mouse wheel
        const wheel = rl.getMouseWheelMove();
        if (wheel != 0) {
            self.camera2d.zoom += wheel * self.config.zoom_speed;
            self.camera2d.zoom = std.math.clamp(self.camera2d.zoom, self.config.min_zoom, self.config.max_zoom);
        }
    }

    fn updateShakeCamera(self: *Self, dt: f32) void {
        if (self.shake_timer > 0) {
            self.shake_timer -= dt;

            // Random shake offset
            const intensity = self.config.shake_intensity * (self.shake_timer / self.config.shake_duration);
            self.shake_offset = Vector2{
                .x = (std.crypto.random.float(f32) - 0.5) * intensity * 2.0,
                .y = (std.crypto.random.float(f32) - 0.5) * intensity * 2.0,
            };
        } else {
            self.shake_offset = Vector2{ .x = 0, .y = 0 };
        }
    }

    fn applyBounds(self: *Self) void {
        if (self.config.bounds) |bounds| {
            self.target_position = bounds.clamp(self.target_position);
        }
    }

    // Public interface
    pub fn setTarget(self: *Self, target: Vector2) void {
        self.follow_target = target;
    }

    pub fn setPosition(self: *Self, position: Vector2) void {
        self.target_position = position;
        self.camera2d.target = position;
    }

    pub fn startShake(self: *Self, intensity: f32, duration: f32) void {
        self.config.shake_intensity = intensity;
        self.config.shake_duration = duration;
        self.shake_timer = duration;
    }

    pub fn setZoom(self: *Self, zoom: f32) void {
        self.camera2d.zoom = std.math.clamp(zoom, self.config.min_zoom, self.config.max_zoom);
    }

    pub fn setBounds(self: *Self, bounds: CameraBounds) void {
        self.config.bounds = bounds;
    }

    pub fn getWorldPosition(self: *Self, screen_pos: Vector2) Vector2 {
        return rl.getScreenToWorld2D(screen_pos, self.camera2d);
    }

    pub fn getScreenPosition(self: *Self, world_pos: Vector2) Vector2 {
        return rl.getWorldToScreen2D(world_pos, self.camera2d);
    }

    pub fn beginMode(self: *Self) void {
        rl.beginMode2D(self.camera2d);
    }

    pub fn endMode(self: *Self) void {
        _ = self;
        rl.endMode2D();
    }
};
