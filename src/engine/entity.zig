const std = @import("std");
const Body = @import("../physics/body.zig").Body;
const rl = @import("raylib");

/// Options for creating entities
pub const EntityOptions = struct {
    texture: ?rl.Texture2D = null,
    visible: bool = true,
};

/// Generic entity that can have various components
pub const Entity = struct {
    id: []const u8,
    body: ?*Body = null,
    texture: ?rl.Texture2D = null,
    visible: bool = true,

    pub fn init(id: []const u8, opts: EntityOptions) Entity {
        return Entity{
            .id = id,
            .body = null, // Will be set by engine
            .texture = opts.texture,
            .visible = opts.visible,
        };
    }

    pub fn draw(self: *const Entity) void {
        if (self.visible and self.body != null) {
            const color = if (self.texture != null) rl.Color.white else rl.Color.red;
            self.body.?.draw(color);
        }
    }
};
