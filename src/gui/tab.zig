const Engine = @import("../engine/engine.zig").Engine;

pub const Tab = struct {
    name: []const u8,
    icon: []const u8,
    description: []const u8,
    func: fn (engine: *Engine) void,
};
