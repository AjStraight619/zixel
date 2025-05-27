const rl = @import("raylib");

pub const Mouse = struct {
    pub const Button = enum {
        left,
        right,
        middle,
    };

    pub fn isButtonPressed(button: Button) bool {
        return rl.isMouseButtonDown(button);
    }

    pub fn isButtonReleased(button: Button) bool {
        return rl.isMouseButtonUp(button);
    }

    pub fn getPosition() rl.Vector2 {
        return rl.getMousePosition();
    }

    pub fn getDelta() rl.Vector2 {
        return rl.getMouseDelta();
    }
};
