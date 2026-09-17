const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const Vec2 = @import("../math/Vec2.zig");

const Input = @This();

pub const MouseButton = enum(u8) {
    left = 0,
    right = 1,
    middle = 2,
};

pub const Key = enum(i32) {
    invalid = 0,
    space = 32,
    apostrophe = 39,
    comma = 44,
    minus = 45,
    period = 46,
    slash = 47,
    @"0" = 48,
    @"1" = 49,
    @"2" = 50,
    @"3" = 51,
    @"4" = 52,
    @"5" = 53,
    @"6" = 54,
    @"7" = 55,
    @"8" = 56,
    @"9" = 57,
    semicolon = 59,
    equal = 61,
    a = 65,
    b = 66,
    c = 67,
    d = 68,
    e = 69,
    f = 70,
    g = 71,
    h = 72,
    i = 73,
    j = 74,
    k = 75,
    l = 76,
    m = 77,
    n = 78,
    o = 79,
    p = 80,
    q = 81,
    r = 82,
    s = 83,
    t = 84,
    u = 85,
    v = 86,
    w = 87,
    x = 88,
    y = 89,
    z = 90,
    left_bracket = 91,
    backslash = 92,
    right_bracket = 93,
    grave_accent = 96,
    escape = 256,
    enter = 257,
    tab = 258,
    backspace = 259,
    insert = 260,
    delete = 261,
    right = 262,
    left = 263,
    down = 264,
    up = 265,
    page_up = 266,
    page_down = 267,
    home = 268,
    end = 269,
    caps_lock = 280,
    scroll_lock = 281,
    num_lock = 282,
    print_screen = 283,
    pause = 284,
    f1 = 290,
    f2 = 291,
    f3 = 292,
    f4 = 293,
    f5 = 294,
    f6 = 295,
    f7 = 296,
    f8 = 297,
    f9 = 298,
    f10 = 299,
    f11 = 300,
    f12 = 301,
    kp_0 = 320,
    kp_1 = 321,
    kp_2 = 322,
    kp_3 = 323,
    kp_4 = 324,
    kp_5 = 325,
    kp_6 = 326,
    kp_7 = 327,
    kp_8 = 328,
    kp_9 = 329,
    kp_decimal = 330,
    kp_divide = 331,
    kp_multiply = 332,
    kp_subtract = 333,
    kp_add = 334,
    kp_enter = 335,
    kp_equal = 336,
    left_shift = 340,
    left_control = 341,
    left_alt = 342,
    left_super = 343,
    right_shift = 344,
    right_control = 345,
    right_alt = 346,
    right_super = 347,
    menu = 348,
    _,
};

const max_keys = 512;

// Key state
keys_down: [max_keys]bool = [_]bool{false} ** max_keys,
keys_pressed: [max_keys]bool = [_]bool{false} ** max_keys,
keys_released: [max_keys]bool = [_]bool{false} ** max_keys,

// Mouse state
mouse_x: f32 = 0,
mouse_y: f32 = 0,
mouse_down: [3]bool = [_]bool{false} ** 3,
mouse_pressed: [3]bool = [_]bool{false} ** 3,
mouse_released: [3]bool = [_]bool{false} ** 3,

// Scroll
scroll_x: f32 = 0,
scroll_y: f32 = 0,

// ============================================================================
// Query methods
// ============================================================================

/// Returns true if key is currently held down
pub fn isKeyDown(self: *const Input, key: Key) bool {
    const idx = self.keyIndex(key);
    return if (idx) |i| self.keys_down[i] else false;
}

/// Returns true if key was just pressed this frame
pub fn isKeyPressed(self: *const Input, key: Key) bool {
    const idx = self.keyIndex(key);
    return if (idx) |i| self.keys_pressed[i] else false;
}

/// Returns true if key was just released this frame
pub fn isKeyReleased(self: *const Input, key: Key) bool {
    const idx = self.keyIndex(key);
    return if (idx) |i| self.keys_released[i] else false;
}

/// Returns current mouse position
pub fn mousePosition(self: *const Input) Vec2 {
    return Vec2.init(self.mouse_x, self.mouse_y);
}

/// Returns true if mouse button is currently held down
pub fn isMouseDown(self: *const Input, button: MouseButton) bool {
    return self.mouse_down[@intFromEnum(button)];
}

/// Returns true if mouse button was just pressed this frame
pub fn isMousePressed(self: *const Input, button: MouseButton) bool {
    return self.mouse_pressed[@intFromEnum(button)];
}

/// Returns true if mouse button was just released this frame
pub fn isMouseReleased(self: *const Input, button: MouseButton) bool {
    return self.mouse_released[@intFromEnum(button)];
}

/// Returns scroll delta for this frame
pub fn scrollDelta(self: *const Input) Vec2 {
    return Vec2.init(self.scroll_x, self.scroll_y);
}

// ============================================================================
// Internal methods (called by Engine)
// ============================================================================

/// Process a sokol event - called by Engine's event callback
pub fn handleEvent(self: *Input, event: *const sapp.Event) void {
    switch (event.type) {
        .KEY_DOWN => {
            // event.key_code is sapp.Keycode enum, convert to int then to our Key
            const key_int: i32 = @intFromEnum(event.key_code);
            if (self.keyIndexFromInt(key_int)) |idx| {
                if (!self.keys_down[idx]) {
                    self.keys_pressed[idx] = true;
                }
                self.keys_down[idx] = true;
            }
        },
        .KEY_UP => {
            const key_int: i32 = @intFromEnum(event.key_code);
            if (self.keyIndexFromInt(key_int)) |idx| {
                self.keys_down[idx] = false;
                self.keys_released[idx] = true;
            }
        },
        .MOUSE_DOWN => {
            const btn: usize = @intCast(@intFromEnum(event.mouse_button));
            if (btn < 3) {
                if (!self.mouse_down[btn]) {
                    self.mouse_pressed[btn] = true;
                }
                self.mouse_down[btn] = true;
            }
        },
        .MOUSE_UP => {
            const btn: usize = @intCast(@intFromEnum(event.mouse_button));
            if (btn < 3) {
                self.mouse_down[btn] = false;
                self.mouse_released[btn] = true;
            }
        },
        .MOUSE_MOVE => {
            self.mouse_x = event.mouse_x;
            self.mouse_y = event.mouse_y;
        },
        .MOUSE_SCROLL => {
            self.scroll_x = event.scroll_x;
            self.scroll_y = event.scroll_y;
        },
        else => {},
    }
}

/// Clear per-frame state - called at end of frame by Engine
pub fn endFrame(self: *Input) void {
    @memset(&self.keys_pressed, false);
    @memset(&self.keys_released, false);
    @memset(&self.mouse_pressed, false);
    @memset(&self.mouse_released, false);
    self.scroll_x = 0;
    self.scroll_y = 0;
}

fn keyIndex(self: *const Input, key: Key) ?usize {
    _ = self;
    const idx: i32 = @intFromEnum(key);
    if (idx >= 0 and idx < max_keys) {
        return @intCast(idx);
    }
    return null;
}

fn keyIndexFromInt(self: *const Input, key_int: i32) ?usize {
    _ = self;
    if (key_int >= 0 and key_int < max_keys) {
        return @intCast(key_int);
    }
    return null;
}
