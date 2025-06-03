const std = @import("std");
const rl = @import("raylib");

/// Simple input manager that only handles RAW input polling
/// Game logic and GUI concerns are handled elsewhere
pub const InputManager = struct {
    const Self = @This();

    pub fn init() Self {
        return Self{};
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Raw keyboard input - just asks raylib "is this key down?"
    pub fn isKeyDown(self: *Self, key: rl.KeyboardKey) bool {
        _ = self;
        return rl.isKeyDown(key);
    }

    pub fn isKeyPressed(self: *Self, key: rl.KeyboardKey) bool {
        _ = self;
        return rl.isKeyPressed(key);
    }

    pub fn isKeyReleased(self: *Self, key: rl.KeyboardKey) bool {
        _ = self;
        return rl.isKeyReleased(key);
    }

    /// Raw mouse input
    pub fn isMouseButtonDown(self: *Self, button: rl.MouseButton) bool {
        _ = self;
        return rl.isMouseButtonDown(button);
    }

    pub fn isMouseButtonPressed(self: *Self, button: rl.MouseButton) bool {
        _ = self;
        return rl.isMouseButtonPressed(button);
    }

    pub fn getMousePosition(self: *Self) rl.Vector2 {
        _ = self;
        return rl.getMousePosition();
    }

    pub fn getMouseDelta(self: *Self) rl.Vector2 {
        _ = self;
        return rl.getMouseDelta();
    }

    /// Convenience functions for common input patterns
    pub fn getMovementInput(self: *Self) rl.Vector2 {
        var movement = rl.Vector2.init(0, 0);

        if (self.isKeyDown(.a) or self.isKeyDown(.left)) movement.x -= 1;
        if (self.isKeyDown(.d) or self.isKeyDown(.right)) movement.x += 1;
        if (self.isKeyDown(.w) or self.isKeyDown(.up)) movement.y -= 1;
        if (self.isKeyDown(.s) or self.isKeyDown(.down)) movement.y += 1;

        // Normalize diagonal movement
        const length = @sqrt(movement.x * movement.x + movement.y * movement.y);
        if (length > 0) {
            movement.x /= length;
            movement.y /= length;
        }

        return movement;
    }

    pub fn isJumpPressed(self: *Self) bool {
        return self.isKeyPressed(.space);
    }

    pub fn isActionPressed(self: *Self) bool {
        return self.isKeyPressed(.j) or self.isKeyPressed(.x);
    }
};
