const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const CacheStats = @import("cache_stats.zig").CacheStats;
const CacheEntry = @import("cache_entry.zig").CacheEntry;
const Asset = @import("cache_entry.zig").Asset;
const log = @import("../core/logging.zig").assets;

pub const AssetCache = struct {
    alloc: Allocator,

    // Asset storage with metadata
    entries: std.StringHashMap(CacheEntry),

    // Configuration
    max_memory_bytes: usize,
    enable_stats: bool,

    // Statistics
    stats: CacheStats,

    const Self = @This();

    pub fn init(alloc: Allocator) Self {
        return Self{
            .alloc = alloc,
            .entries = std.StringHashMap(CacheEntry).init(alloc),
            .max_memory_bytes = @as(usize, @intFromFloat(256.0 * 1024.0 * 1024.0)),
            .enable_stats = true,
            .stats = CacheStats{},
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            self.unloadAsset(entry.value_ptr.asset);
        }
        self.entries.deinit();

        if (self.enable_stats) {
            log.info("Final cache stats: {}", .{self.stats});
        }
    }

    // Simplified texture loading for now
    fn loadTextureFromDisk(self: *Self, full_path: [:0]const u8) !rl.Texture {
        _ = self;
        return rl.loadTexture(full_path) catch |err| {
            log.err("Failed to load texture: {s}", .{full_path});
            return err;
        };
    }

    // Type-specific public methods
    pub fn getTexture(self: *Self, full_path: [:0]const u8) !rl.Texture {
        // Make a copy of the path for the hash map key
        const path_copy = try self.alloc.dupe(u8, full_path);

        const result = try self.entries.getOrPut(path_copy);

        if (result.found_existing) {
            // Cache hit - free the path copy since we didn't need it
            self.alloc.free(path_copy);
            if (self.enable_stats) self.stats.hits += 1;
            result.value_ptr.touch();

            return switch (result.value_ptr.asset) {
                .Texture => |tex| tex,
                else => error.AssetTypeMismatch,
            };
        }

        // Cache miss - load new texture (keep path_copy as the key)
        if (self.enable_stats) self.stats.misses += 1;

        const texture = try self.loadTextureFromDisk(full_path);
        const entry = CacheEntry{
            .asset = Asset{ .Texture = texture },
            .size_bytes = CacheEntry.estimateSize(Asset{ .Texture = texture }),
            .last_accessed = std.time.timestamp(),
        };

        result.value_ptr.* = entry;
        self.stats.total_memory_bytes += entry.size_bytes;

        return texture;
    }

    pub fn getSound(self: *Self, full_path: []const u8) !rl.Sound {
        return self.getCachedAsset(full_path, Asset.Sound);
    }

    pub fn getMusic(self: *Self, full_path: []const u8) !rl.Music {
        return self.getCachedAsset(full_path, Asset.Music);
    }

    pub fn getFont(self: *Self, full_path: []const u8) !rl.Font {
        return self.getCachedAsset(full_path, Asset.Font);
    }

    // Helper functions
    fn loadAssetFromDisk(self: *Self, full_path: []const u8, comptime asset_type: Asset) Asset {
        _ = self;
        return switch (asset_type) {
            Asset.Texture => Asset{ .Texture = rl.loadTexture(full_path) },
            Asset.Sound => Asset{ .Sound = rl.loadSound(full_path) },
            Asset.Music => Asset{ .Music = rl.loadMusicStream(full_path) },
            Asset.Font => Asset{ .Font = rl.loadFont(full_path) },
        };
    }

    fn unloadAsset(self: *Self, asset: Asset) void {
        _ = self;
        switch (asset) {
            .Texture => |tex| rl.unloadTexture(tex),
            .Sound => |sound| rl.unloadSound(sound),
            .Music => |music| rl.unloadMusicStream(music),
            .Font => |font| rl.unloadFont(font),
        }
    }

    // Simple LRU eviction (to be improved later)
    fn evictOldAssets(self: *Self, needed_bytes: usize) !void {
        var freed_bytes: usize = 0;

        // Simple strategy: remove oldest accessed assets that can be evicted
        var iterator = self.entries.iterator();
        var oldest_time: i64 = std.time.timestamp();
        var oldest_key: ?[]const u8 = null;

        while (iterator.next()) |entry| {
            if (entry.value_ptr.canEvict() and entry.value_ptr.last_accessed < oldest_time) {
                oldest_time = entry.value_ptr.last_accessed;
                oldest_key = entry.key_ptr.*;
            }
        }

        if (oldest_key) |key| {
            const entry = self.entries.get(key).?;
            freed_bytes = entry.size_bytes;
            self.unloadAsset(entry.asset);
            _ = self.entries.remove(key);
            self.stats.total_memory_bytes -= freed_bytes;
            self.stats.evictions += 1;
        }

        // If we still need more space, we might need multiple evictions
        if (freed_bytes < needed_bytes and self.entries.count() > 0) {
            try self.evictOldAssets(needed_bytes - freed_bytes);
        }
    }

    // Public API for cache management
    pub fn getStats(self: Self) CacheStats {
        return self.stats;
    }

    pub fn printStats(self: Self) void {
        if (self.enable_stats) {
            self.stats.print();
        }
    }

    pub fn pinAsset(self: *Self, path: []const u8) void {
        if (self.entries.getPtr(path)) |entry| {
            entry.is_pinned = true;
        }
    }

    pub fn unpinAsset(self: *Self, path: []const u8) void {
        if (self.entries.getPtr(path)) |entry| {
            entry.is_pinned = false;
        }
    }
};
