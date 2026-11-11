const std = @import("std");
const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;

const CountingAllocator = @This();

parent_allocator: Allocator,
alloc_size: u64 = 0,
free_size: u64 = 0,

pub fn init(parent_allocator: Allocator) CountingAllocator {
    return .{ .parent_allocator = parent_allocator };
}

pub fn deinit(self: *CountingAllocator) void {
    self.* = undefined;
}

pub fn allocator(self: *CountingAllocator) Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        },
    };
}

pub fn liveSize(self: *CountingAllocator) u64 {
    return self.alloc_size - self.free_size;
}

fn alloc(ctx: *anyopaque, len: usize, ptr_align: Alignment, ret_addr: usize) ?[*]u8 {
    const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
    const result = self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);
    // Count only memory that was actually handed out.
    if (result != null) self.alloc_size += len;
    return result;
}

fn resize(ctx: *anyopaque, buf: []u8, buf_align: Alignment, new_len: usize, ret_addr: usize) bool {
    const self: *CountingAllocator = @ptrCast(@alignCast(ctx));

    if (self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr)) {
        if (new_len > buf.len) {
            self.alloc_size += new_len - buf.len;
        } else {
            self.free_size += buf.len - new_len;
        }
        return true;
    } else {
        return false;
    }
}

fn remap(ctx: *anyopaque, buf: []u8, buf_align: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
    if (self.parent_allocator.rawRemap(buf, buf_align, new_len, ret_addr)) |remapped| {
        if (new_len > buf.len) {
            self.alloc_size += new_len - buf.len;
        } else {
            self.free_size += buf.len - new_len;
        }
        return remapped;
    }
    return null;
}

fn free(ctx: *anyopaque, buf: []u8, buf_align: Alignment, ret_addr: usize) void {
    const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
    self.free_size += buf.len;
    return self.parent_allocator.rawFree(buf, buf_align, ret_addr);
}

test "failed allocations are not counted as live memory" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var counting = CountingAllocator.init(failing.allocator());
    const a = counting.allocator();
    const first = try a.alloc(u8, 32);
    try std.testing.expectError(error.OutOfMemory, a.alloc(u8, 1000));
    try std.testing.expectEqual(@as(u64, 32), counting.liveSize());
    a.free(first);
    try std.testing.expectEqual(@as(u64, 0), counting.liveSize());
}
