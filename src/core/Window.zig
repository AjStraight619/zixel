const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;

pub const Window = @This();

cfg: Config = DefaultWindowConfig,

const DefaultWindowConfig = Config{};

pub const Config = struct {
    width: u32 = 1024,
    height: u32 = 768,
    title: []const u8 = "Zixel New",
    fullscreen: bool = false,
    resizable: bool = true,
    vsync: bool = true,
    multisampling: u32 = 0,
    windowed_aspect_ratio: f32 = 16.0 / 9.0,
};
