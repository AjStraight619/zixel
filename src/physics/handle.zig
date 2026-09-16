const std = @import("std");

/// A generational handle for safely referencing bodies.
///
/// This provides O(1) lookup and detects stale references:
/// - `index` points to a slot in the storage array
/// - `generation` is bumped each time a slot is reused
///
/// If you hold a handle and the body is removed, then a new body
/// takes that slot, your handle's generation won't match - the lookup
/// will return null instead of the wrong body.
pub const BodyHandle = struct {
    index: u32,
    generation: u32,

    pub const invalid = BodyHandle{
        .index = std.math.maxInt(u32),
        .generation = 0,
    };

    pub fn isValid(self: BodyHandle) bool {
        return self.index != std.math.maxInt(u32);
    }

    pub fn eql(self: BodyHandle, other: BodyHandle) bool {
        return self.index == other.index and self.generation == other.generation;
    }

    pub fn format(self: BodyHandle, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (!self.isValid()) {
            try writer.writeAll("BodyHandle(invalid)");
        } else {
            try writer.print("BodyHandle({d}:{d})", .{ self.index, self.generation });
        }
    }
};

test "BodyHandle basics" {
    const h1 = BodyHandle{ .index = 0, .generation = 1 };
    const h2 = BodyHandle{ .index = 0, .generation = 2 };
    const h3 = BodyHandle{ .index = 0, .generation = 1 };

    try std.testing.expect(h1.isValid());
    try std.testing.expect(!BodyHandle.invalid.isValid());
    try std.testing.expect(!h1.eql(h2)); // same slot, different generation
    try std.testing.expect(h1.eql(h3)); // same slot and generation
}
