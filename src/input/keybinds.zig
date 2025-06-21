const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const Key = @import("keys.zig").Key;

/// Input behavior types for actions
pub const InputBehavior = enum {
    tap, // Just pressed this frame (good for jumping, shooting, menu navigation)
    hold, // Currently held down (good for movement, charging)
    release, // Just released this frame (good for releasing charged attacks)
};

/// Generic keybind manager that works with any user-defined enum
pub fn KeybindManager(comptime ActionType: type) type {
    // Ensure ActionType is an enum
    const type_info = @typeInfo(ActionType);
    if (type_info != .@"enum") {
        @compileError("ActionType must be an enum");
    }

    return struct {
        alloc: Allocator,
        bindings: std.AutoHashMap(ActionType, Key),
        consumed_keys: std.ArrayList(rl.KeyboardKey),

        const Self = @This();

        pub fn init(alloc: Allocator) Self {
            return Self{
                .alloc = alloc,
                .bindings = std.AutoHashMap(ActionType, Key).init(alloc),
                .consumed_keys = std.ArrayList(rl.KeyboardKey).init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            self.bindings.deinit();
            self.consumed_keys.deinit();
        }

        /// Call at the start of each frame to reset consumed keys
        pub fn beginFrame(self: *Self) void {
            self.consumed_keys.clearRetainingCapacity();
        }

        /// Bind an action to a key
        pub fn bind(self: *Self, action: ActionType, key: Key) !void {
            try self.bindings.put(action, key);
        }

        /// Bind multiple actions at once using a struct literal
        ///
        /// Example:
        /// ```zig
        /// try keybind_mgr.bindMany(.{
        ///     .move_left = .left,
        ///     .move_right = .right,
        ///     .jump = .space,
        /// });
        /// ```
        ///
        /// The struct fields must:
        /// - Have names that match your ActionType enum variants
        /// - Have values of type `Key`
        pub fn bindMany(self: *Self, bindings: anytype) !void {
            comptime {
                const T = @TypeOf(bindings);
                const info = @typeInfo(T);
                if (info != .@"struct") {
                    @compileError("bindMany() expects a struct literal like .{ .move_left = .left, .jump = .space }");
                }

                // Validate each field at compile time
                for (info.@"struct".fields) |field| {
                    // Allow Key type or enum literals (which get coerced to Key)
                    if (field.type != Key and field.type != @TypeOf(.enum_literal)) {
                        @compileError("All binding values must be of type Key or enum literal, found " ++ @typeName(field.type) ++ " for field '" ++ field.name ++ "'");
                    }
                }
            }

            const fields = std.meta.fields(@TypeOf(bindings));
            inline for (fields) |field| {
                const action = @field(ActionType, field.name);
                const key = @field(bindings, field.name);
                try self.bind(action, key);
            }
        }

        /// Check if an action is active with specified behavior
        /// This is the main method for flexible input handling
        pub fn isAction(self: *Self, action: ActionType, behavior: InputBehavior) bool {
            if (self.bindings.get(action)) |key| {
                if (self.isKeyConsumed(key)) return false;

                return switch (behavior) {
                    .tap => rl.isKeyPressed(key), // Just pressed this frame
                    .hold => rl.isKeyDown(key), // Currently held down
                    .release => rl.isKeyReleased(key), // Just released this frame
                };
            }
            return false;
        }

        /// Check if an action is active with specified behavior AND consume the key
        /// Use this when you want to prevent other systems from seeing the same input
        pub fn isActionConsumed(self: *Self, action: ActionType, behavior: InputBehavior) !bool {
            if (self.bindings.get(action)) |key| {
                if (self.isKeyConsumed(key)) return false;

                const is_active = switch (behavior) {
                    .tap => rl.isKeyPressed(key), // Just pressed this frame
                    .hold => rl.isKeyDown(key), // Currently held down
                    .release => rl.isKeyReleased(key), // Just released this frame
                };

                if (is_active) {
                    try self.consumeKey(key);
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

        /// Get the key bound to an action (returns null if not bound)
        pub fn getKey(self: *Self, action: ActionType) ?Key {
            return self.bindings.get(action);
        }

        /// Remove a binding
        pub fn unbind(self: *Self, action: ActionType) void {
            _ = self.bindings.remove(action);
        }

        /// Check if an action is bound to any key
        pub fn isBound(self: *Self, action: ActionType) bool {
            return self.bindings.contains(action);
        }

        // Private helper methods
        fn isKeyConsumed(self: *const Self, key: rl.KeyboardKey) bool {
            for (self.consumed_keys.items) |consumed_key| {
                if (consumed_key == key) return true;
            }
            return false;
        }

        fn consumeKey(self: *Self, key: rl.KeyboardKey) !void {
            try self.consumed_keys.append(key);
        }
    };
}

/// Helper function to create a keybind manager for any enum type
pub fn createKeybindManager(comptime ActionType: type, alloc: Allocator) KeybindManager(ActionType) {
    return KeybindManager(ActionType).init(alloc);
}
