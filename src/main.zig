const std = @import("std");
const zixel = @import("zixel_new");

pub fn main() void {
    var engine = zixel.Engine.init(std.heap.page_allocator, .{});
    engine.run();
}
