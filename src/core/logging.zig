const std = @import("std");

const build_options = @import("build_options");

// Configuration for runtime log level control
pub const LogConfig = struct {
    physics_level: std.log.Level = .info,
    graphics_level: std.log.Level = .info,
    assets_level: std.log.Level = .info,
    engine_level: std.log.Level = .info,
    gui_level: std.log.Level = .info,
    input_level: std.log.Level = .info,
    renderer_level: std.log.Level = .info,
    general_level: std.log.Level = .info,
};

// Global config (can be modified at runtime)
var global_config = LogConfig{};

// Initialize from environment variables if available
pub fn initFromEnv() void {
    // Check for ZIXEL_LOG_LEVEL environment variable
    if (std.posix.getenv("ZIXEL_LOG_LEVEL")) |level_str| {
        if (std.mem.eql(u8, level_str, "debug")) {
            setAllLogLevels(.debug);
        } else if (std.mem.eql(u8, level_str, "info")) {
            setAllLogLevels(.info);
        } else if (std.mem.eql(u8, level_str, "warn")) {
            setAllLogLevels(.warn);
        } else if (std.mem.eql(u8, level_str, "err")) {
            setAllLogLevels(.err);
        }
    }

    // Check for specific subsystem overrides
    if (std.posix.getenv("ZIXEL_PHYSICS_LOG")) |level_str| {
        if (parseLogLevel(level_str)) |level| {
            setLogLevel("physics", level);
        }
    }

    if (std.posix.getenv("ZIXEL_ASSETS_LOG")) |level_str| {
        if (parseLogLevel(level_str)) |level| {
            setLogLevel("assets", level);
        }
    }
}

fn parseLogLevel(level_str: []const u8) ?std.log.Level {
    if (std.mem.eql(u8, level_str, "debug")) return .debug;
    if (std.mem.eql(u8, level_str, "info")) return .info;
    if (std.mem.eql(u8, level_str, "warn")) return .warn;
    if (std.mem.eql(u8, level_str, "err")) return .err;
    return null;
}

// Get the build-time log level (with proper type conversion)
pub fn getBuildLogLevel() std.log.Level {
    return switch (build_options.log_level) {
        .debug => .debug,
        .info => .info,
        .warn => .warn,
        .err => .err,
    };
}

// Get build-time feature flags
pub fn isDebugEnabled() bool {
    return build_options.enable_debug_features;
}

pub fn isProfilingEnabled() bool {
    return build_options.enable_profiling;
}

pub fn isPhysicsDebugEnabled() bool {
    return build_options.physics_debug;
}

// Define scoped loggers for different engine subsystems
pub const physics = std.log.scoped(.physics);
pub const graphics = std.log.scoped(.graphics);
pub const assets = std.log.scoped(.assets);
pub const engine = std.log.scoped(.engine);
pub const gui = std.log.scoped(.gui);
pub const input = std.log.scoped(.input);
pub const renderer = std.log.scoped(.renderer);

// General purpose logger (falls back to default std.log)
pub const general = std.log.scoped(.zixel);

// Helper functions for common logging patterns with level checking
pub fn debugCollision(comptime fmt: []const u8, args: anytype) void {
    if (@intFromEnum(global_config.physics_level) <= @intFromEnum(std.log.Level.debug)) {
        physics.debug(fmt, args);
    }
}

pub fn infoAssetLoad(comptime fmt: []const u8, args: anytype) void {
    if (@intFromEnum(global_config.assets_level) <= @intFromEnum(std.log.Level.info)) {
        assets.info(fmt, args);
    }
}

pub fn warnInput(comptime fmt: []const u8, args: anytype) void {
    if (@intFromEnum(global_config.input_level) <= @intFromEnum(std.log.Level.warn)) {
        input.warn(fmt, args);
    }
}

pub fn errorEngine(comptime fmt: []const u8, args: anytype) void {
    if (@intFromEnum(global_config.engine_level) <= @intFromEnum(std.log.Level.err)) {
        engine.err(fmt, args);
    }
}

// Compile-time conditional logging for performance-critical paths
pub fn debugPhysics(comptime fmt: []const u8, args: anytype) void {
    if (comptime isPhysicsDebugEnabled()) {
        physics.debug(fmt, args);
    }
}

pub fn debugProfile(comptime fmt: []const u8, args: anytype) void {
    if (comptime isProfilingEnabled()) {
        general.debug(fmt, args);
    }
}

// Configuration functions
pub fn setLogLevel(subsystem: []const u8, level: std.log.Level) void {
    if (std.mem.eql(u8, subsystem, "physics")) {
        global_config.physics_level = level;
    } else if (std.mem.eql(u8, subsystem, "graphics")) {
        global_config.graphics_level = level;
    } else if (std.mem.eql(u8, subsystem, "assets")) {
        global_config.assets_level = level;
    } else if (std.mem.eql(u8, subsystem, "engine")) {
        global_config.engine_level = level;
    } else if (std.mem.eql(u8, subsystem, "gui")) {
        global_config.gui_level = level;
    } else if (std.mem.eql(u8, subsystem, "input")) {
        global_config.input_level = level;
    } else if (std.mem.eql(u8, subsystem, "renderer")) {
        global_config.renderer_level = level;
    } else if (std.mem.eql(u8, subsystem, "general")) {
        global_config.general_level = level;
    }
}

pub fn setAllLogLevels(level: std.log.Level) void {
    global_config.physics_level = level;
    global_config.graphics_level = level;
    global_config.assets_level = level;
    global_config.engine_level = level;
    global_config.gui_level = level;
    global_config.input_level = level;
    global_config.renderer_level = level;
    global_config.general_level = level;
}

pub fn disableLogging(subsystem: []const u8) void {
    setLogLevel(subsystem, .err); // Only show errors
}

pub fn enableDebugLogging(subsystem: []const u8) void {
    setLogLevel(subsystem, .debug); // Show everything
}

// Preset configurations
pub fn setQuietMode() void {
    setAllLogLevels(.warn); // Only warnings and errors
}

pub fn setVerboseMode() void {
    setAllLogLevels(.debug); // Show everything
}

pub fn setProductionMode() void {
    setAllLogLevels(.err); // Only errors
}

// Initialize logging system with build-time defaults
pub fn init() void {
    // Set runtime config to match build-time defaults
    setAllLogLevels(getBuildLogLevel());

    // Then apply environment overrides
    initFromEnv();

    // Log the initialization
    general.info("Zixel logging initialized - build log level: {}, debug features: {}, profiling: {}", .{
        getBuildLogLevel(),
        isDebugEnabled(),
        isProfilingEnabled(),
    });
}
