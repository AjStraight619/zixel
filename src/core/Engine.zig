const std = @import("std");
const Allocator = std.mem.Allocator;
const Scene = @import("Scene.zig");

pub const Engine = @This();

cfg: Config = DefaultEngineConfig,
alloc: Allocator,
scenes: std.ArrayList(Scene) = .empty,
mode: Mode = .production,

pub const Config = struct {
    // TODO: fps config here
};

pub const Mode = enum { debug, production };

const DefaultEngineConfig = Config{};

// TODO: Accept a flag to turn to debug mode
pub fn init(alloc: Allocator, cfg: Config) Engine {
    return .{
        .cfg = cfg orelse DefaultEngineConfig,
        .alloc = alloc,
        .scenes = .empty,
        .mode = .production,
    };
}

pub fn run() !void {}

// pub fn createScene(self: *Engine, ) {

// }
