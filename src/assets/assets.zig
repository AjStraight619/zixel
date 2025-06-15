const std = @import("std");
const rl = @import("raylib");
const AssetCache = @import("cache.zig").AssetCache;

pub const Assets = struct {
    _cache: AssetCache,
    base_path: [:0]const u8,
    auto_cache: bool,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, base_path: [:0]const u8) Self {
        return Self{
            ._cache = AssetCache.init(alloc),
            .base_path = base_path,
            .auto_cache = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self._cache.deinit();
    }

    // Helper to build full paths
    fn buildPath(self: *Self, path: [:0]const u8) ![:0]const u8 {
        const joined = try std.fs.path.join(self._cache.alloc, &[_][]const u8{ self.base_path, path });
        defer self._cache.alloc.free(joined); // Free the intermediate result
        // Convert to null-terminated string for raylib
        return try self._cache.alloc.dupeZ(u8, joined);
    }

    // Clean public API methods
    pub fn loadTexture(self: *Self, path: [:0]const u8) !rl.Texture {
        const full_path = try self.buildPath(path);
        defer self._cache.alloc.free(full_path);

        if (self.auto_cache) {
            return self._cache.getTexture(full_path);
        } else {
            return rl.loadTexture(full_path);
        }
    }

    pub fn loadSound(self: *Self, path: [:0]const u8) !rl.Sound {
        const full_path = try self.buildPath(path);
        defer self._cache.alloc.free(full_path);

        if (self.auto_cache) {
            return self._cache.getSound(full_path);
        } else {
            return rl.loadSound(full_path);
        }
    }

    pub fn loadMusic(self: *Self, path: [:0]const u8) !rl.Music {
        const full_path = try self.buildPath(path);
        defer self._cache.alloc.free(full_path);

        if (self.auto_cache) {
            return self._cache.getMusic(full_path);
        } else {
            return rl.loadMusicStream(full_path);
        }
    }

    pub fn loadFont(self: *Self, path: [:0]const u8) !rl.Font {
        const full_path = try self.buildPath(path);
        defer self._cache.alloc.free(full_path);

        if (self.auto_cache) {
            return self._cache.getFont(full_path);
        } else {
            return rl.loadFont(full_path);
        }
    }

    // Control caching
    pub fn setAutoCaching(self: *Self, enabled: bool) void {
        self.auto_cache = enabled;
    }
};

test "path building correctness" {
    var assets = Assets.init(std.testing.allocator, "test-assets");
    defer assets.deinit();

    // Test that buildPath correctly joins base_path + relative path
    const full_path = try assets.buildPath("kenney_pattern-pack-pixel/Tiles (Color)/tile_0001.png");
    defer assets._cache.alloc.free(full_path);

    const expected = "test-assets/kenney_pattern-pack-pixel/Tiles (Color)/tile_0001.png";
    try std.testing.expectEqualStrings(expected, full_path);
}

test "auto caching toggle" {
    var assets = Assets.init(std.testing.allocator, "test-assets");
    defer assets.deinit();

    // Test that auto_cache starts as true
    try std.testing.expect(assets.auto_cache == true);

    // Test that we can toggle it
    assets.setAutoCaching(false);
    try std.testing.expect(assets.auto_cache == false);

    assets.setAutoCaching(true);
    try std.testing.expect(assets.auto_cache == true);
}

test "cache stats tracking through assets API" {
    var assets = Assets.init(std.testing.allocator, "test-assets");
    defer assets.deinit();

    // Initial cache stats should be zero
    const initial_stats = assets._cache.getStats();
    try std.testing.expect(initial_stats.hits == 0);
    try std.testing.expect(initial_stats.misses == 0);
    try std.testing.expect(initial_stats.total_memory_bytes == 0);

    // Test that we can access cache stats through the Assets API
    // This verifies the high-level API exposes the cache functionality
    try std.testing.expect(assets._cache.enable_stats == true);
}
