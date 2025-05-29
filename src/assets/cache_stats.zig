const std = @import("std");

pub const CacheStats = struct {
    hits: u64 = 0,
    misses: u64 = 0,
    total_memory_bytes: usize = 0,
    evictions: u64 = 0,

    const Self = @This();

    pub fn getHitRatio(self: Self) f32 {
        const total = self.hits + self.misses;
        if (total == 0) return 0.0;
        return @as(f32, @floatFromInt(self.hits)) / @as(f32, @floatFromInt(total));
    }

    pub fn reset(self: *Self) void {
        self.hits = 0;
        self.misses = 0;
        self.evictions = 0;
        // Keep total_memory_bytes as it represents current state
    }

    pub fn print(self: Self) void {
        std.log.info("Cache Stats:");
        std.log.info("  Hits: {}, Misses: {}", .{ self.hits, self.misses });
        std.log.info("  Hit Ratio: {d:.2}%", .{self.getHitRatio() * 100});
        std.log.info("  Memory: {d:.2} MB", .{@as(f32, @floatFromInt(self.total_memory_bytes)) / (1024.0 * 1024.0)});
        std.log.info("  Evictions: {}", .{self.evictions});
    }
};
