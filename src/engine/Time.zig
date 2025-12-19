const std = @import("std");
const sokol = @import("sokol");
const stime = sokol.time;

const Time = @This();

pub const Config = struct {
    /// Clamp huge dt spikes (alt-tab / breakpoint).
    max_dt: f32 = 1.0 / 15.0, // 66ms

    /// Engine-wide timescale (slow-mo, fast-forward).
    time_scale: f32 = 1.0,

    /// Fixed-step settings (for physics / deterministic sim).
    fixed_dt: f32 = 1.0 / 60.0,

    /// FPS smoothing factor (EMA alpha). 0.1 = fairly smooth.
    fps_alpha: f32 = 0.1,
};

cfg: Config = .{},

// raw timing
last_ticks: u64 = 0,
dt_raw: f32 = 0,

// scaled timing
dt: f32 = 0,
time: f64 = 0, // total scaled time
frame: u64 = 0,

// fixed-step accumulator (scaled dt)
accum: f32 = 0,

// controls
paused: bool = false,
step_once: bool = false,

// lightweight fps tracking
fps_smooth: f32 = 0.0,
fps_initialized: bool = false,

/// Value-style init so Engine can do `.time = Time.init(cfg.time)`.
pub fn init(cfg: Config) Time {
    stime.setup();
    return .{
        .cfg = cfg,
        .last_ticks = stime.now(),
        .dt_raw = 0,
        .dt = 0,
        .time = 0,
        .frame = 0,
        .accum = 0,
        .paused = false,
        .step_once = false,
        .fps_smooth = 0.0,
        .fps_initialized = false,
    };
}

/// Call once per rendered frame.
pub fn beginFrame(self: *Time) void {
    self.frame += 1;

    const ticks_now = stime.now();
    const delta_ticks = stime.diff(ticks_now, self.last_ticks);
    self.last_ticks = ticks_now;

    var dt_raw64: f64 = stime.sec(delta_ticks);
    if (dt_raw64 < 0) dt_raw64 = 0;
    if (dt_raw64 > @as(f64, self.cfg.max_dt)) dt_raw64 = @as(f64, self.cfg.max_dt);

    const dt_raw: f32 = @floatCast(dt_raw64);
    self.dt_raw = dt_raw;

    // Apply pause + optional single-step
    if (self.paused) {
        if (self.step_once) {
            self.step_once = false;
            self.dt = dt_raw * self.cfg.time_scale;
        } else {
            self.dt = 0;
        }
    } else {
        self.dt = dt_raw * self.cfg.time_scale;
    }

    self.time += @as(f64, self.dt);
    self.accum += self.dt;

    const fps_inst: f32 = if (dt_raw > 0) 1.0 / dt_raw else 0.0;
    if (!self.fps_initialized) {
        if (fps_inst > 0) {
            self.fps_smooth = fps_inst;
            self.fps_initialized = true;
        }
    } else {
        const a = std.math.clamp(self.cfg.fps_alpha, 0.0, 1.0);
        self.fps_smooth = self.fps_smooth * (1.0 - a) + fps_inst * a;
    }
}

/// Consume fixed steps (run your deterministic sim while this returns true).
pub fn popFixedStep(self: *Time) bool {
    if (self.cfg.fixed_dt <= 0) return false;

    if (self.accum >= self.cfg.fixed_dt) {
        self.accum -= self.cfg.fixed_dt;
        return true;
    }
    return false;
}

/// Interpolation alpha for rendering between fixed steps.
pub fn alpha(self: *const Time) f32 {
    if (self.cfg.fixed_dt <= 0) return 0;
    return @min(self.accum / self.cfg.fixed_dt, 1.0);
}

pub fn pause(self: *Time) void {
    self.paused = true;
}

pub fn unpause(self: *Time) void {
    self.paused = false;
}

pub fn togglePause(self: *Time) void {
    self.paused = !self.paused;
}

pub fn stepFrame(self: *Time) void {
    self.step_once = true;
}

// --- tests that don't depend on sokol-time ---

test "popFixedStep consumes accum and alpha clamps" {
    var t = Time{
        .cfg = .{ .fixed_dt = 0.1, .fps_alpha = 0.1 },
        .last_ticks = 0,
        .dt_raw = 0,
        .dt = 0,
        .time = 0,
        .frame = 0,
        .accum = 0,
        .paused = false,
        .step_once = false,
        .fps_smooth = 0,
        .fps_initialized = true,
    };

    t.accum = 0.25;
    try std.testing.expect(t.popFixedStep()); // -> 0.15
    try std.testing.expect(t.popFixedStep()); // -> 0.05
    try std.testing.expect(!t.popFixedStep());

    try std.testing.expectApproxEqAbs(@as(f32, 0.5), t.alpha(), 0.0001);

    t.accum = 1.0;
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), t.alpha(), 0.0001);
}
