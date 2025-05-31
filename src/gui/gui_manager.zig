const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const rlg = @import("raygui");
const Engine = @import("../engine/engine.zig").Engine;
const DebugPanel = @import("debug_panel.zig").DebugPanel;
const ObjectCreation = @import("object_creation.zig").ObjectCreation;
const Window = @import("../renderer/window.zig").Window;

pub const Tab = enum(i32) {
    debug_panel = 0,
    object_creation = 1,
};

pub const GUI = struct {
    alloc: Allocator,
    debug_panel: DebugPanel,
    object_creation: ObjectCreation,
    active_tab: Tab = .debug_panel,
    show_gui: bool = true,
    main_rect: rl.Rectangle,
    total_tabs: u32 = 2,

    const Self = @This();

    pub fn init(alloc: Allocator, window: *const Window) Self {
        const window_size = window.getWindowSize();
        return Self{
            .alloc = alloc,
            .debug_panel = DebugPanel.init(),
            .object_creation = ObjectCreation.init(alloc),
            .main_rect = rl.Rectangle{
                .x = 10,
                .y = 10,
                .width = @floatFromInt(@divFloor(window_size.windowWidth, 4)),
                .height = @floatFromInt(@divFloor(window_size.windowHeight, 2)),
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.object_creation.deinit();
    }

    pub fn update(self: *Self, engine: *Engine) void {
        if (!self.show_gui) return;

        // Main container window with close button
        const close_result = rlg.windowBox(self.main_rect, "Game Tools");
        if (close_result == 1) {
            self.show_gui = false;
            return;
        }

        // Tab area
        const tab_height: f32 = 30;
        const tab_rect = rl.Rectangle{
            .x = self.main_rect.x + 5,
            .y = self.main_rect.y + 25, // Below window title bar
            .width = self.main_rect.width / @as(f32, @floatFromInt(self.total_tabs)) - 5, // Center tabs and split them evenly - 5 for padding right
            .height = tab_height,
        };

        var active_tab_int: i32 = @intFromEnum(self.active_tab);
        const toggle_result = rlg.toggleGroup(tab_rect, "Debug;Objects", &active_tab_int);
        if (toggle_result >= 0) {
            self.active_tab = @enumFromInt(active_tab_int);
        }

        // Content area (below tabs)
        const content_rect = rl.Rectangle{
            .x = self.main_rect.x + 5,
            .y = self.main_rect.y + 25 + tab_height + 5,
            .width = self.main_rect.width - 10,
            .height = self.main_rect.height - 60 - tab_height,
        };

        // Render active tab content
        self.renderActiveTab(engine, content_rect);
    }

    fn renderActiveTab(self: *Self, engine: *Engine, content_rect: rl.Rectangle) void {
        switch (self.active_tab) {
            .debug_panel => self.debug_panel.render(engine, content_rect),
            .object_creation => self.object_creation.render(engine, content_rect),
        }
    }

    pub fn switchTab(_: *Self) void {}

    pub fn toggleVisibility(self: *Self) void {
        self.show_gui = !self.show_gui;
    }

    pub fn toggleDebugPanel(self: *Self) void {
        self.toggleVisibility();
    }

    pub fn isDebugPanelVisible(self: *const Self) bool {
        return self.show_gui;
    }
};
