const std = @import("std");
const zixel = @import("zixel_new");
const Allocator = std.mem.Allocator;

const Editor = @This();

alloc: Allocator,

world: ?*zixel.World = null,

selected_entity: ?usize = null,

show_scene_view: bool = true,
show_hierarchy: bool = true,
show_inspector: bool = true,
show_console: bool = true,
show_demo: bool = false,

console_lines: std.ArrayList([]const u8),

pub fn init(alloc: Allocator) Editor {
    return .{
        .alloc = alloc,
        .console_lines = .empty,
    };
}

pub fn deinit(self: *Editor) void {
    self.console_lines.deinit(self.alloc);
}

pub fn log(self: *Editor, msg: []const u8) void {
    // In a real app, you'd dup this string, but for now just storing the slice
    self.console_lines.append(self.alloc, msg) catch {};
}

pub fn clearLog(self: *Editor) void {
    self.console_lines.clearRetainingCapacity();
}
