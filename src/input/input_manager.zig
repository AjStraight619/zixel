const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const KeybindManager = @import("keybinds.zig").KeybindManager;
const Key = @import("keys.zig").Key;
const GUIManager = @import("../gui/gui_manager.zig").GUI;
const Engine = @import("../engine/engine.zig").Engine;

// Type aliases for clean function signatures
const HandleInputFn = @import("../engine/engine.zig").HandleInputFn;

/// GUI-specific actions that can be bound to keys
pub const GuiAction = enum {
    toggle_debug_panel,
    close_dialog,
    confirm,
    cancel,
};

/// Input behavior types for actions
pub const InputBehavior = enum {
    tap, // Just pressed this frame (good for jumping, shooting, menu navigation)
    hold, // Currently held down (good for movement, charging)
    release, // Just released this frame (good for releasing charged attacks)
};

/// Input contexts - determines which inputs are active
pub const InputContext = enum {
    game, // Normal gameplay - both game and GUI toggle actions work
    gui, // GUI is open - only GUI actions work, game actions blocked
    menu, // In menu - only menu navigation works
};

/// Input manager that works with any user-defined action enum
pub fn InputManager(comptime ActionType: type) type {
    return struct {
        alloc: Allocator,
        keybind_manager: KeybindManager(ActionType),
        gui_keybinds: std.AutoHashMap(GuiAction, Key),
        consumed_keys: std.ArrayList(rl.KeyboardKey),
        current_context: InputContext = .game,

        const Self = @This();

        pub fn init(alloc: Allocator) Self {
            return Self{
                .alloc = alloc,
                .keybind_manager = KeybindManager(ActionType).init(alloc),
                .gui_keybinds = std.AutoHashMap(GuiAction, Key).init(alloc),
                .consumed_keys = std.ArrayList(rl.KeyboardKey).init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            self.keybind_manager.deinit();
            self.gui_keybinds.deinit();
            self.consumed_keys.deinit();
        }

        /// Bind an action to a key - users call this directly on InputManager
        pub fn bind(self: *Self, action: ActionType, key: Key) !void {
            try self.keybind_manager.bind(action, key);
        }

        /// Bind multiple actions at once using a struct literal
        pub fn bindMany(self: *Self, bindings: anytype) !void {
            try self.keybind_manager.bindMany(bindings);
        }

        /// Remove a binding
        pub fn unbind(self: *Self, action: ActionType) void {
            self.keybind_manager.unbind(action);
        }

        /// Check if an action is bound to any key
        pub fn isBound(self: *Self, action: ActionType) bool {
            return self.keybind_manager.isBound(action);
        }

        /// Get the key bound to an action (returns null if not bound)
        pub fn getKey(self: *Self, action: ActionType) ?Key {
            return self.keybind_manager.getKey(action);
        }

        /// Load default GUI keybinds
        pub fn loadDefaultGuiBindings(self: *Self) !void {
            try self.gui_keybinds.put(.toggle_debug_panel, .g);
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
        pub fn setGuiKeybind(self: *Self, action: GuiAction, key: Key) !void {
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
                const raylib_key = key.toRaylib();
                if (rl.isKeyPressed(raylib_key) and !self.isKeyConsumed(raylib_key)) {
                    try self.consumeKey(raylib_key);
                    return true;
                }
            }
            return false;
        }

        /// Check if an action is active with specified behavior (tap/hold/release)
        /// This is the main method for flexible input handling
        pub fn isAction(self: *Self, action: ActionType, behavior: InputBehavior) bool {
            // Block game actions when in GUI context
            if (self.current_context == .gui) return false;

            if (self.keybind_manager.getKey(action)) |key| {
                const raylib_key = key.toRaylib();
                if (self.isKeyConsumed(raylib_key)) return false;

                return switch (behavior) {
                    .tap => rl.isKeyPressed(raylib_key), // Just pressed this frame
                    .hold => rl.isKeyDown(raylib_key), // Currently held down
                    .release => rl.isKeyReleased(raylib_key), // Just released this frame
                };
            }
            return false;
        }

        /// Check if an action is active with specified behavior AND consume the key
        /// Use this when you want to prevent other systems from seeing the same input
        pub fn isActionConsumed(self: *Self, action: ActionType, behavior: InputBehavior) !bool {
            // Block game actions when in GUI context
            if (self.current_context == .gui) return false;

            if (self.keybind_manager.getKey(action)) |key| {
                const raylib_key = key.toRaylib();
                if (self.isKeyConsumed(raylib_key)) return false;

                const is_active = switch (behavior) {
                    .tap => rl.isKeyPressed(raylib_key), // Just pressed this frame
                    .hold => rl.isKeyDown(raylib_key), // Currently held down
                    .release => rl.isKeyReleased(raylib_key), // Just released this frame
                };

                if (is_active) {
                    try self.consumeKey(raylib_key);
                    return true;
                }
            }
            return false;
        }

        /// Convenience methods for common input patterns
        /// Check if action was just pressed (tap behavior)
        pub fn isActionTapped(self: *Self, action: ActionType) bool {
            return self.isAction(action, .tap);
        }

        /// Check if action is currently held down (hold behavior)
        pub fn isActionHeld(self: *Self, action: ActionType) bool {
            return self.isAction(action, .hold);
        }

        /// Check if action was just released (release behavior)
        pub fn isActionReleased(self: *Self, action: ActionType) bool {
            return self.isAction(action, .release);
        }

        /// Convenience methods with consumption
        /// Check if action was just pressed and consume it
        pub fn isActionTappedConsumed(self: *Self, action: ActionType) !bool {
            return self.isActionConsumed(action, .tap);
        }

        /// Check if action is held and consume it
        pub fn isActionHeldConsumed(self: *Self, action: ActionType) !bool {
            return self.isActionConsumed(action, .hold);
        }

        /// Check if action was released and consume it
        pub fn isActionReleasedConsumed(self: *Self, action: ActionType) !bool {
            return self.isActionConsumed(action, .release);
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
}
