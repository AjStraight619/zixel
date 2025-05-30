const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");

// Define all possible game actions
pub const GameAction = enum {
    MoveUp,
    MoveDown,
    MoveLeft,
    MoveRight,
    Jump,
    Attack,
    Interact,
    OpenMenu,
};

pub const KeybindManager = struct {
    alloc: Allocator,
    // Using a HashMap to store action -> key mappings.
    bindings: std.AutoHashMap(GameAction, rl.KeyboardKey),

    const Self = @This();

    pub fn init(alloc: Allocator) Self {
        return Self{
            .alloc = alloc,
            .bindings = std.AutoHashMap(GameAction, rl.KeyboardKey).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        self.bindings.deinit();
    }

    // Register a key for a specific action
    pub fn addBinding(self: *Self, action: GameAction, key: rl.KeyboardKey) !void {
        try self.bindings.put(action, key);
    }

    // Default bindings
    pub fn loadDefaultBindings(self: *Self) !void {
        try self.addBinding(.MoveUp, .up);
        try self.addBinding(.MoveDown, .down);
        try self.addBinding(.MoveLeft, .left);
        try self.addBinding(.MoveRight, .right);
        try self.addBinding(.Jump, .space);
        try self.addBinding(.Attack, .j);
        try self.addBinding(.Interact, .e);
        try self.addBinding(.OpenMenu, .escape);
    }

    // Check if an action's key is currently held down
    pub fn isActionPressed(self: *Self, action: GameAction) bool {
        if (self.bindings.get(action)) |key| {
            return rl.isKeyDown(key);
        } else {
            std.log.warn("No binding found for action: {any}", .{action});
            return false;
        }
    }

    // Check if an action's key was just pressed in this frame
    pub fn isActionJustPressed(self: *Self, action: GameAction) bool {
        if (self.bindings.get(action)) |key| {
            return rl.isKeyPressed(key);
        } else {
            // It's good to log if a binding is missing, but you might not want to spam logs every frame.
            // Consider logging this only once or during a debug mode.
            // std.log.debug("No binding found for action (just pressed): {any}", .{action});
            return false;
        }
    }

    // Check if an action's key was just released in this frame
    pub fn isActionReleased(self: *Self, action: GameAction) bool {
        if (self.bindings.get(action)) |key| {
            return rl.isKeyReleased(key);
        } else {
            // std.log.debug("No binding found for action (released): {any}", .{action});
            return false;
        }
    }

    // TODO: Add functionality for rebinding keys at runtime (e.g., load/save from config file).
};
