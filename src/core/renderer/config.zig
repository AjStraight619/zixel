pub const WindowConfig = struct {
    width: u32,
    height: u32,
    title: [:0]const u8, // Need to match the C string type
};
