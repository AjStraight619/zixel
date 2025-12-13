const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;

pub const ArgParseError = error{
    InvalidArgument,
    MissingValue,
    TooManyPositionals,
};

pub const RunMode = enum { edit, play };

pub const Command = union(enum) {
    run: RunArgs,
    help: void,
};

pub const RunArgs = struct {
    mode: RunMode = .edit,
    scene_path: ?[]const u8 = null,
};

const ArgKind = union(enum) {
    help,
    edit,
    play,
    scene_flag,
    positional: []const u8,
    unknown: []const u8,
};

fn classifyArg(arg: []const u8) ArgKind {
    if (mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "-h")) return .help;
    if (mem.eql(u8, arg, "--edit")) return .edit;
    if (mem.eql(u8, arg, "--play")) return .play;
    if (mem.eql(u8, arg, "--scene")) return .scene_flag;

    // positional = doesn't start with '-'
    if (arg.len > 0 and arg[0] != '-') return .{ .positional = arg };

    return .{ .unknown = arg };
}

pub fn parseArgs(alloc: Allocator) (ArgParseError || Allocator.Error)!Command {
    var it = try std.process.argsWithAllocator(alloc);
    defer it.deinit();

    _ = it.next(); // skip argv[0]

    var run: RunArgs = .{};
    var positional_count: u32 = 0;
    var saw_scene_flag: bool = false;

    while (it.next()) |arg| {
        switch (classifyArg(arg)) {
            .help => return .help,

            .edit => run.mode = .edit,
            .play => run.mode = .play,

            .scene_flag => {
                const value = it.next() orelse return error.MissingValue;

                // If you want to allow both, remove this check.
                if (run.scene_path != null) return error.TooManyPositionals;

                run.scene_path = value;
                saw_scene_flag = true;
            },

            .positional => |p| {
                positional_count += 1;
                if (positional_count > 1) return error.TooManyPositionals;

                // If user already used --scene, don’t also accept a positional.
                if (saw_scene_flag) return error.TooManyPositionals;

                run.scene_path = p;
            },

            .unknown => return error.InvalidArgument,
        }
    }

    return .{ .run = run };
}
