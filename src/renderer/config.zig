pub const WindowConfig = struct {
    width: u32 = 800,
    height: u32 = 600,
    title: [:0]const u8 = "Zig2D", // Need to match the C string type
};
