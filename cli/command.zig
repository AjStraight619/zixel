pub const help = @import("help.zig");
pub const version = @import("version.zig");
pub const new = @import("new.zig");

pub const NewArgs = @import("NewArgs.zig");

pub const Command = union(enum) {
    help: void,
    version: void,
    new: NewArgs,
};
