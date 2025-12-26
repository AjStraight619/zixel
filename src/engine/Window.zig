const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;

const Window = @This();

pub const Config = struct {
    width: i32 = 1024,
    height: i32 = 768,
    title: [:0]const u8 = "Zixel",
    fullscreen: bool = false,
    high_dpi: bool = true,
    sample_count: i32 = 1,
    swap_interval: i32 = 1,
};
