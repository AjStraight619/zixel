// const std = @import("std");
//
// pub fn build(b: *std.Build) !void {
//     const target = b.standardTargetOptions(.{});
//     const optimize = b.standardOptimizeOption(.{});
//
//     // sokol-zig dependency
//     const dep_sokol = b.dependency("sokol", .{
//         .target = target,
//         .optimize = optimize,
//     });
//
//     const mod_sokol = dep_sokol.module("sokol");
//
//     // Main library module
//     const mod = b.addModule("zixel_new", .{
//         .root_source_file = b.path("src/root.zig"),
//         .target = target,
//         .optimize = optimize,
//         .imports = &.{
//             .{ .name = "sokol", .module = mod_sokol },
//         },
//     });
//
//     // Main executable
//     const exe = b.addExecutable(.{
//         .name = "zixel_new",
//         .root_module = b.createModule(.{
//             .root_source_file = b.path("src/main.zig"),
//             .target = target,
//             .optimize = optimize,
//             .imports = &.{
//                 .{ .name = "zixel_new", .module = mod },
//                 .{ .name = "sokol", .module = mod_sokol },
//             },
//         }),
//     });
//
//     b.installArtifact(exe);
//
//     const run_step = b.step("run", "Run the app");
//     const run_cmd = b.addRunArtifact(exe);
//     run_step.dependOn(&run_cmd.step);
//     run_cmd.step.dependOn(b.getInstallStep());
//
//     if (b.args) |args| {
//         run_cmd.addArgs(args);
//     }
//
//     // Sample: render_example
//     const render_example = b.addExecutable(.{
//         .name = "render_example",
//         .root_module = b.createModule(.{
//             .root_source_file = b.path("samples/render_example.zig"),
//             .target = target,
//             .optimize = optimize,
//             .imports = &.{
//                 .{ .name = "zixel_new", .module = mod },
//                 .{ .name = "sokol", .module = mod_sokol },
//             },
//         }),
//     });
//     b.installArtifact(render_example);
//
//     const run_render_example = b.step("run-render-example", "Run the render example");
//     const run_render_cmd = b.addRunArtifact(render_example);
//     run_render_example.dependOn(&run_render_cmd.step);
//     run_render_cmd.step.dependOn(b.getInstallStep());
//
//     // Sample: physics_example
//     const physics_example = b.addExecutable(.{
//         .name = "physics_example",
//         .root_module = b.createModule(.{
//             .root_source_file = b.path("samples/physics_example.zig"),
//             .target = target,
//             .optimize = optimize,
//             .imports = &.{
//                 .{ .name = "zixel_new", .module = mod },
//                 .{ .name = "sokol", .module = mod_sokol },
//             },
//         }),
//     });
//     b.installArtifact(physics_example);
//
//     const run_physics_example = b.step("run-physics-example", "Run the physics example");
//     const run_physics_cmd = b.addRunArtifact(physics_example);
//     run_physics_example.dependOn(&run_physics_cmd.step);
//     run_physics_cmd.step.dependOn(b.getInstallStep());
//
//     // Sample: ramps_example (circles rolling down ramps)
//     const ramps_example = b.addExecutable(.{
//         .name = "ramps_example",
//         .root_module = b.createModule(.{
//             .root_source_file = b.path("samples/ramps_example.zig"),
//             .target = target,
//             .optimize = optimize,
//             .imports = &.{
//                 .{ .name = "zixel_new", .module = mod },
//                 .{ .name = "sokol", .module = mod_sokol },
//             },
//         }),
//     });
//     b.installArtifact(ramps_example);
//
//     const run_ramps_example = b.step("run-ramps-example", "Run the ramps example");
//     const run_ramps_cmd = b.addRunArtifact(ramps_example);
//     run_ramps_example.dependOn(&run_ramps_cmd.step);
//     run_ramps_cmd.step.dependOn(b.getInstallStep());
//
//     // Tests
//     const mod_tests = b.addTest(.{ .root_module = mod });
//     const run_mod_tests = b.addRunArtifact(mod_tests);
//     const exe_tests = b.addTest(.{ .root_module = exe.root_module });
//     const run_exe_tests = b.addRunArtifact(exe_tests);
//
//     const test_step = b.step("test", "Run tests");
//     test_step.dependOn(&run_mod_tests.step);
//     test_step.dependOn(&run_exe_tests.step);
// }

const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // sokol-zig dependency
    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });
    const mod_sokol = dep_sokol.module("sokol");

    // Main library module
    const mod = b.addModule("zixel_new", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = mod_sokol },
        },
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "zixel_new",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zixel_new", .module = mod },
                .{ .name = "sokol", .module = mod_sokol },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // ---------------------------------------------------------------------
    // Samples (only refactor this section)
    // ---------------------------------------------------------------------
    const Sample = struct {
        exe_name: []const u8, // artifact name
        file: []const u8, // root source file
        run_step: []const u8, // zig build <run_step>
        desc: []const u8, // step description
    };

    const samples = [_]Sample{
        .{
            .exe_name = "render_example",
            .file = "samples/render_example.zig",
            .run_step = "run-render-example",
            .desc = "Run the render example",
        },
        .{
            .exe_name = "physics_example",
            .file = "samples/physics_example.zig",
            .run_step = "run-physics-example",
            .desc = "Run the physics example",
        },
        .{
            .exe_name = "ramps_example",
            .file = "samples/ramps_example.zig",
            .run_step = "run-ramps-example",
            .desc = "Run the ramps example",
        },
        .{
            .exe_name = "angular_vel_example",
            .file = "samples/angular_vel_example.zig",
            .run_step = "run-angular-vel-example",
            .desc = "Run the angular velocity example",
        },
    };

    inline for (samples) |s| {
        const sample_exe = b.addExecutable(.{
            .name = s.exe_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(s.file),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zixel_new", .module = mod },
                    .{ .name = "sokol", .module = mod_sokol },
                },
            }),
        });
        b.installArtifact(sample_exe);

        const run_sample_step = b.step(s.run_step, s.desc);
        const run_sample_cmd = b.addRunArtifact(sample_exe);
        run_sample_step.dependOn(&run_sample_cmd.step);
        run_sample_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_sample_cmd.addArgs(args);
        }
    }

    // Tests
    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
