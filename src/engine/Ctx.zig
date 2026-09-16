const std = @import("std");
const Allocator = std.mem.Allocator;

const World = @import("World.zig");
const Physics = @import("../physics/Physics.zig");
const Renderer = @import("Renderer.zig");
const Input = @import("Input.zig");

const Ctx = @This();

alloc: Allocator,
world: *World,
physics: *Physics,
renderer: *Renderer,
input: *Input,
