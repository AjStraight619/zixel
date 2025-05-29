const std = @import("std");
const rl = @import("raylib");
const AssetCache = @import("cache.zig").AssetCache;

pub const Assets = struct {
    _cache: AssetCache,
    base_path: []const u8,
    auto_cache: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, base_path: []const u8) Self {
        return Self{
            ._cache = AssetCache.init(allocator),
            .base_path = base_path,
            .auto_cache = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.cache.deinit();
    }

    // Helper to build full paths
    fn buildPath(self: *Self, path: []const u8) ![]const u8 {
        return try std.fs.path.join(self.cache.allocator, &[_][]const u8{ self.base_path, path });
    }

    // Clean public API methods
    pub fn loadTexture(self: *Self, path: []const u8) !rl.Texture {
        const full_path = try self.buildPath(path);
        defer self.cache.allocator.free(full_path);

        if (self.auto_cache) {
            return self.cache.getTexture(full_path);
        } else {
            return rl.loadTexture(full_path);
        }
    }

    pub fn loadSound(self: *Self, path: []const u8) !rl.Sound {
        const full_path = try self.buildPath(path);
        defer self.cache.allocator.free(full_path);

        if (self.auto_cache) {
            return self.cache.getSound(full_path);
        } else {
            return rl.loadSound(full_path);
        }
    }

    pub fn loadMusic(self: *Self, path: []const u8) !rl.Music {
        const full_path = try self.buildPath(path);
        defer self.cache.allocator.free(full_path);

        if (self.auto_cache) {
            return self.cache.getMusic(full_path);
        } else {
            return rl.loadMusicStream(full_path);
        }
    }

    pub fn loadFont(self: *Self, path: []const u8) !rl.Font {
        const full_path = try self.buildPath(path);
        defer self.cache.allocator.free(full_path);

        if (self.auto_cache) {
            return self.cache.getFont(full_path);
        } else {
            return rl.loadFont(full_path);
        }
    }

    // Control caching
    pub fn setAutoCaching(self: *Self, enabled: bool) void {
        self.auto_cache = enabled;
    }
};
