const std = @import("std");
const Allocator = std.mem.Allocator;

const World = @import("../physics/World.zig");
const Renderer = @import("Renderer.zig");
const Input = @import("Input.zig");

const Ctx = @This();

alloc: Allocator,
world: *World,
renderer: *Renderer,
input: *Input,
