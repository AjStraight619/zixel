const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const Key = @import("keys.zig").Key;

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

        const Self = @This();

        pub fn init(alloc: Allocator) Self {
            return Self{
                .alloc = alloc,
                .bindings = std.AutoHashMap(ActionType, Key).init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            self.bindings.deinit();
        }

        /// Bind an action to a key
        pub fn bind(self: *Self, action: ActionType, key: Key) !void {
            try self.bindings.put(action, key);
        }

        /// Bind multiple actions at once using a struct literal
        pub fn bindMany(self: *Self, bindings: anytype) !void {
            const fields = std.meta.fields(@TypeOf(bindings));
            inline for (fields) |field| {
                const action = @field(ActionType, field.name);
                const key = @field(bindings, field.name);
                try self.bind(action, key);
            }
        }

        /// Check if an action's key is currently held down
        pub fn isActionHeld(self: *Self, action: ActionType) bool {
            if (self.bindings.get(action)) |key| {
                return rl.isKeyDown(key.toRaylib());
            }
            return false;
        }

        /// Check if an action's key was just pressed this frame
        pub fn isActionTapped(self: *Self, action: ActionType) bool {
            if (self.bindings.get(action)) |key| {
                return rl.isKeyPressed(key.toRaylib());
            }
            return false;
        }

        /// Check if an action's key was just released this frame
        pub fn isActionReleased(self: *Self, action: ActionType) bool {
            if (self.bindings.get(action)) |key| {
                return rl.isKeyReleased(key.toRaylib());
            }
            return false;
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
    };
}

/// Helper function to create a keybind manager for any enum type
pub fn createKeybindManager(comptime ActionType: type, alloc: Allocator) KeybindManager(ActionType) {
    return KeybindManager(ActionType).init(alloc);
}
