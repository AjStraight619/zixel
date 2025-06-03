const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const rlg = @import("raygui");
const Engine = @import("../ecs/engine.zig").Engine;
const DebugPanel = @import("debug_panel.zig").DebugPanel;
const ObjectCreation = @import("object_creation.zig").ObjectCreation;

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

    // Responsive design constants
    const MIN_WIDTH: f32 = 300;
    const MAX_WIDTH: f32 = 500;
    const MIN_HEIGHT: f32 = 400;
    const MAX_HEIGHT: f32 = 700;
    const MARGIN: f32 = 10;

    pub fn init(alloc: Allocator) Self {
        var self = Self{
            .alloc = alloc,
            .debug_panel = DebugPanel.init(),
            .object_creation = ObjectCreation.init(alloc),
            .main_rect = undefined, // Will be calculated
        };

        // Calculate initial responsive dimensions
        self.updateResponsiveDimensions();
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.object_creation.deinit();
    }

    /// Calculate responsive dimensions based on current window size
    fn updateResponsiveDimensions(self: *Self) void {
        const screen_width = @as(f32, @floatFromInt(rl.getScreenWidth()));
        const screen_height = @as(f32, @floatFromInt(rl.getScreenHeight()));

        // Calculate optimal width (prefer 25% of screen width, but respect min/max)
        var optimal_width = screen_width * 0.25;

        // For very small screens, use a larger percentage
        if (screen_width < 800) {
            optimal_width = screen_width * 0.4;
        }

        // Apply constraints
        const panel_width = std.math.clamp(optimal_width, MIN_WIDTH, @min(MAX_WIDTH, screen_width - 2 * MARGIN));

        // Calculate optimal height based on aspect ratio and screen size
        var optimal_height: f32 = undefined;

        if (screen_height < 600) {
            // For small heights, use more of the screen
            optimal_height = screen_height * 0.8;
        } else if (screen_height < 800) {
            optimal_height = screen_height * 0.6;
        } else {
            optimal_height = screen_height * 0.5;
        }

        // Apply height constraints
        const panel_height = std.math.clamp(optimal_height, MIN_HEIGHT, @min(MAX_HEIGHT, screen_height - 2 * MARGIN));

        // Position the panel (LEFT side of screen, like it was before)
        self.main_rect = rl.Rectangle{
            .x = MARGIN,
            .y = MARGIN,
            .width = panel_width,
            .height = panel_height,
        };
    }

    pub fn update(self: *Self, engine: *Engine) void {
        if (!self.show_gui) return;

        // Update responsive dimensions if window was resized
        if (engine.isWindowResized()) {
            self.updateResponsiveDimensions();
        }

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

        // Content area (below tabs) - make it scrollable if needed
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

    /// Get the current layout info for responsive content
    pub fn getLayoutInfo(self: *const Self) LayoutInfo {
        return LayoutInfo{
            .is_compact = self.main_rect.width < 350 or self.main_rect.height < 500,
            .is_narrow = self.main_rect.width < 350,
            .is_short = self.main_rect.height < 500,
            .available_width = self.main_rect.width - 20, // Account for margins
            .available_height = self.main_rect.height - 90, // Account for title and tabs
        };
    }
};

pub const LayoutInfo = struct {
    is_compact: bool,
    is_narrow: bool,
    is_short: bool,
    available_width: f32,
    available_height: f32,
};
