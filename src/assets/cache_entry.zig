const std = @import("std");
const rl = @import("raylib");

pub const AssetType = enum {
    Texture,
    Sound,
    Music,
    Font,
};

pub const Asset = union(AssetType) {
    Texture: rl.Texture,
    Sound: rl.Sound,
    Music: rl.Music,
    Font: rl.Font,
};

/// Enhanced cache entry with metadata for advanced caching strategies
pub const CacheEntry = struct {
    asset: Asset,
    size_bytes: usize,
    last_accessed: i64, // Timestamp for LRU
    ref_count: u32 = 1,
    is_pinned: bool = false, // Prevent eviction if true

    const Self = @This();

    pub fn touch(self: *Self) void {
        self.last_accessed = std.time.timestamp();
        self.ref_count += 1;
    }

    pub fn release(self: *Self) void {
        if (self.ref_count > 0) {
            self.ref_count -= 1;
        }
    }

    pub fn canEvict(self: Self) bool {
        return !self.is_pinned and self.ref_count == 0;
    }

    pub fn estimateSize(asset: Asset) usize {
        return switch (asset) {
            .Texture => |tex| @as(usize, @intCast(tex.width * tex.height * 4)), // Assume RGBA
            .Sound => 44100 * 2 * 2, // Rough estimate: 1 second stereo 16-bit
            .Music => 1024 * 1024, // Rough estimate: 1MB stream buffer
            .Font => 512 * 1024, // Rough estimate: 512KB font
        };
    }
};
