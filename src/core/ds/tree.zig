const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Tree(comptime T: type) type {
    return struct {
        const Node = struct {
            value: T,
            children: std.ArrayList(*Node),
        };
        const Self = @This();
    };
}
