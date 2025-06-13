const rl = @import("raylib");
const Assets = @import("../assets/assets.zig").Assets;

pub const Sprite = struct {
    texture: rl.Texture,
    source_rect: ?rl.Rectangle = null, // For sprite sheets
    scale: rl.Vector2 = rl.Vector2.init(1.0, 1.0),
    rotation_offset: f32 = 0.0, // Additional rotation beyond physics body
    tint: rl.Color = rl.Color.white,
    z_index: i32 = 0, // For layering

    /// Create a sprite from a texture file path (will be cached automatically)
    pub fn fromFile(assets: *Assets, path: []const u8) !Sprite {
        const texture = try assets.loadTexture(path);
        return Sprite{ .texture = texture };
    }

    /// Create a sprite from an already loaded texture
    pub fn fromTexture(texture: rl.Texture) Sprite {
        return Sprite{ .texture = texture };
    }

    /// Create a sprite with custom scale
    pub fn fromFileWithScale(assets: *Assets, path: []const u8, scale: rl.Vector2) !Sprite {
        const texture = try assets.loadTexture(path);
        return Sprite{ .texture = texture, .scale = scale };
    }

    /// Create a sprite from sprite sheet (specific rectangle within texture)
    pub fn fromSpriteSheet(assets: *Assets, path: []const u8, source_rect: rl.Rectangle) !Sprite {
        const texture = try assets.loadTexture(path);
        return Sprite{ .texture = texture, .source_rect = source_rect };
    }

    /// Create a sprite with full customization
    pub fn fromFileCustom(assets: *Assets, path: []const u8, opts: struct {
        source_rect: ?rl.Rectangle = null,
        scale: rl.Vector2 = rl.Vector2.init(1.0, 1.0),
        rotation_offset: f32 = 0.0,
        tint: rl.Color = rl.Color.white,
        z_index: i32 = 0,
    }) !Sprite {
        const texture = try assets.loadTexture(path);
        return Sprite{
            .texture = texture,
            .source_rect = opts.source_rect,
            .scale = opts.scale,
            .rotation_offset = opts.rotation_offset,
            .tint = opts.tint,
            .z_index = opts.z_index,
        };
    }
};
