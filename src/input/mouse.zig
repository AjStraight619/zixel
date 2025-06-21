const rl = @import("raylib");
const MouseButton = rl.MouseButton;
const MouseCursor = rl.MouseCursor;

pub const Mouse = struct {
    pub const Button = MouseButton;
    pub const Cursor = MouseCursor;

    pub fn isMouseDown(button: Button) bool {
        return rl.isMouseButtonDown(button);
    }

    pub fn isMouseUp(button: Button) bool {
        return rl.isMouseButtonUp(button);
    }

    pub fn getPosition() rl.Vector2 {
        return rl.getMousePosition();
    }

    pub fn getDelta() rl.Vector2 {
        return rl.getMouseDelta();
    }

    pub fn getMouseX() f32 {
        return rl.getMouseX();
    }

    pub fn getMouseY() f32 {
        return rl.getMouseY();
    }

    pub fn setCursor(cursor: Cursor) void {
        rl.setMouseCursor(cursor);
    }

    pub fn enabledCursor() void {
        rl.enableCursor();
    }

    pub fn disabledCursor() void {
        rl.disableCursor();
    }

    pub fn showCursor() void {
        rl.showCursor();
    }

    pub fn hideCursor() void {
        rl.hideCursor();
    }
};
