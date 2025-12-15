const std = @import("std");

pub const TimeConfig = struct {
    max_delta_time: f32 = 0.1,
    fps_sample_window_s: f32 = 0.25,
    target_fps: f32 = 0,
    min_fps_hint: f32 = 0,
};

pub const FrameStats = struct {
    dt: f32 = 0,
    fps: f32 = 0,
    ms: f32 = 0,

    // windowed average internals
    _accum_s: f32 = 0,
    _frames: u32 = 0,

    pub fn tick(self: *FrameStats, cfg: TimeConfig, raw_dt: f32) void {
        // clamp dt
        const dt = @min(raw_dt, cfg.max_delta_time);
        self.dt = dt;

        // accumulate for FPS smoothing
        self._frames += 1;
        self._accum_s += dt;

        if (self._accum_s >= cfg.fps_sample_window_s) {
            const avg_dt = self._accum_s / @as(f32, @floatFromInt(self._frames));
            self.fps = if (avg_dt > 0) 1.0 / avg_dt else 0;
            self.ms = avg_dt * 1000.0;
            self._frames = 0;
            self._accum_s = 0;
        }
    }
};
