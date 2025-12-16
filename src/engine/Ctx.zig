const std = @import("std");
const Allocator = std.mem.Allocator;

const World = @import("../physics/world.zig");
const Renderer = @import("Renderer.zig");
const Input = @import("Input.zig");

pub const Ctx = struct {
    alloc: Allocator,
    world: *World,
    renderer: *Renderer,
    input: *Input,
};
