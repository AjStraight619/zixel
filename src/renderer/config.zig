pub const WindowConfig = struct {
    width: u32 = 800,
    height: u32 = 600,
    title: [:0]const u8 = "zixel", // Need to match the C string type
};
