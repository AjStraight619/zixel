//! The executable owns log policy. Runtime modules only emit scoped std.log calls.
const std = @import("std");
const Logger = @import("zixel_new").logging.Logger;

// Set before starting callbacks/threads; unset after all producers have stopped.
pub var active: ?*Logger = null;

pub fn logFn(comptime level: std.log.Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype) void {
    if (active) |logger| {
        logger.log(level, scope, format, args);
    } else if (level != .debug) {
        std.log.defaultLog(level, scope, format, args);
    }
}

pub fn panic(message: []const u8, return_address: ?usize) noreturn {
    if (active) |logger| logger.recordPanic(message);
    // Preserve Zig's normal stderr stack trace and termination behavior.
    std.debug.defaultPanic(message, return_address);
}
