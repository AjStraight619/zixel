pub const help = @import("help.zig");
pub const version = @import("version.zig");
pub const new = @import("new.zig");
pub const init = @import("init.zig");

pub const NewArgs = struct {
    name: []const u8,
    sample: ?[]const u8 = null,
};

pub const Command = union(enum) {
    help: void,
    version: void,
    new: NewArgs,
};
