const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const rlg = @import("raygui");
const Engine = @import("../engine/engine.zig").Engine;
const DebugPanel = @import("debug_panel.zig").DebugPanel;

pub const GUI = struct {
    alloc: Allocator,
    debug_panel: DebugPanel,

    const Self = @This();

    pub fn init(alloc: Allocator) Self {
        return Self{
            .alloc = alloc,
            .debug_panel = DebugPanel.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // No cleanup needed yet
    }

    pub fn update(self: *Self, engine: *Engine) void {
        // Update debug panel (input handling is done centrally by InputManager)
        self.debug_panel.update(engine);
    }

    pub fn toggleDebugPanel(self: *Self) void {
        self.debug_panel.toggleVisibility();
    }

    pub fn isDebugPanelVisible(self: *const Self) bool {
        return self.debug_panel.isVisible();
    }
};
