const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const KeybindManager = @import("keybinds.zig").KeybindManager;
const GUIManager = @import("../gui/gui_manager.zig").GUI;
const Engine = @import("../engine/engine.zig").Engine;

// Type aliases for clean function signatures
const HandleInputFn = @import("../engine/engine.zig").HandleInputFn;
const GameAction = @import("keybinds.zig").GameAction;

/// GUI-specific actions that can be bound to keys
pub const GuiAction = enum {
    toggle_debug_panel,
    close_dialog,
    confirm,
    cancel,
};

/// Input contexts - determines which inputs are active
pub const InputContext = enum {
    game, // Normal gameplay - both game and GUI toggle actions work
    gui, // GUI is open - only GUI actions work, game actions blocked
    menu, // In menu - only menu navigation works
};

/// Manages all input with priority and consumption system
pub const InputManager = struct {
    alloc: Allocator,
    keybind_manager: *KeybindManager,
    gui_keybinds: std.AutoHashMap(GuiAction, rl.KeyboardKey),
    consumed_keys: std.ArrayList(rl.KeyboardKey),
    current_context: InputContext = .game,

    const Self = @This();

    pub fn init(alloc: Allocator, keybind_manager: *KeybindManager) Self {
        return Self{
            .alloc = alloc,
            .keybind_manager = keybind_manager,
            .gui_keybinds = std.AutoHashMap(GuiAction, rl.KeyboardKey).init(alloc),
            .consumed_keys = std.ArrayList(rl.KeyboardKey).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        self.gui_keybinds.deinit();
        self.consumed_keys.deinit();
    }

    /// Load default GUI keybinds
    pub fn loadDefaultGuiBindings(self: *Self) !void {
        try self.gui_keybinds.put(.toggle_debug_panel, .f1);
        try self.gui_keybinds.put(.close_dialog, .escape);
        try self.gui_keybinds.put(.confirm, .enter);
        try self.gui_keybinds.put(.cancel, .escape);
    }

    /// Set the current input context
    pub fn setContext(self: *Self, context: InputContext) void {
        self.current_context = context;
    }

    /// Get the current input context
    pub fn getContext(self: *const Self) InputContext {
        return self.current_context;
    }

    /// Set a GUI keybind (for user customization)
    pub fn setGuiKeybind(self: *Self, action: GuiAction, key: rl.KeyboardKey) !void {
        try self.gui_keybinds.put(action, key);
    }

    /// Check if a key was consumed this frame
    pub fn isKeyConsumed(self: *const Self, key: rl.KeyboardKey) bool {
        for (self.consumed_keys.items) |consumed_key| {
            if (consumed_key == key) return true;
        }
        return false;
    }

    /// Mark a key as consumed (prevents lower priority handlers from seeing it)
    fn consumeKey(self: *Self, key: rl.KeyboardKey) !void {
        try self.consumed_keys.append(key);
    }

    /// Check if a GUI action key was pressed (and consume it if so)
    pub fn isGuiActionPressed(self: *Self, action: GuiAction) !bool {
        if (self.gui_keybinds.get(action)) |key| {
            if (rl.isKeyPressed(key) and !self.isKeyConsumed(key)) {
                try self.consumeKey(key);
                return true;
            }
        }
        return false;
    }

    /// Check if a game action key was pressed (only if not consumed and context allows)
    pub fn isGameActionPressed(self: *Self, action: GameAction) bool {
        // Block game actions when in GUI context
        if (self.current_context == .gui) return false;

        if (self.keybind_manager.bindings.get(action)) |key| {
            return rl.isKeyPressed(key) and !self.isKeyConsumed(key);
        }
        return false;
    }

    /// Handle all input with proper prioritization and context switching
    /// Returns true if any input was consumed
    pub fn handleInput(self: *Self, gui: *GUIManager, game_input_fn: ?HandleInputFn, engine: *Engine) !bool {
        // Clear consumed keys from previous frame
        self.consumed_keys.clearRetainingCapacity();

        var input_consumed = false;

        switch (self.current_context) {
            .game => {
                // In game context: GUI toggle actions + game actions work

                // GUI Toggle (can switch to GUI context)
                if (try self.isGuiActionPressed(.toggle_debug_panel)) {
                    gui.toggleDebugPanel();
                    // If GUI is now visible, switch to GUI context
                    if (gui.isDebugPanelVisible()) {
                        self.setContext(.gui);
                    }
                    input_consumed = true;
                }

                // Game Input (only if no GUI action consumed input)
                if (!input_consumed and game_input_fn != null) {
                    if (game_input_fn) |input_fn| {
                        try input_fn(engine, self.alloc);
                    }
                }
            },

            .gui => {
                // In GUI context: only GUI actions work, game actions blocked

                // GUI Toggle (can switch back to game context)
                if (try self.isGuiActionPressed(.toggle_debug_panel)) {
                    gui.toggleDebugPanel();
                    // If GUI is now hidden, switch back to game context
                    if (!gui.isDebugPanelVisible()) {
                        self.setContext(.game);
                    }
                    input_consumed = true;
                }

                // Close actions (ESC key)
                if (try self.isGuiActionPressed(.close_dialog)) {
                    gui.toggleDebugPanel(); // Close the panel
                    self.setContext(.game); // Switch back to game
                    input_consumed = true;
                }

                // Game input is blocked in GUI context
            },

            .menu => {
                // In menu context: only menu actions work (not implemented yet)
                // This would be for main menu, pause menu, etc.
            },
        }

        return input_consumed;
    }
};
