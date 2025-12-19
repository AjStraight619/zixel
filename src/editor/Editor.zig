const std = @import("std");
const Allocator = std.mem.Allocator;

const sokol = @import("sokol");
const sapp = sokol.app;
const simgui = sokol.imgui;

const ig = @import("cimgui");

const World = @import("../physics/world.zig");

pub const Editor = @This();

alloc: Allocator,
world: ?*World = null,
initialized: bool = false,

// Panel visibility
show_scene_view: bool = true,
show_hierarchy: bool = true,
show_inspector: bool = true,
show_console: bool = true,

// Selection state
selected_entity: ?usize = null,

// Console log
console_lines: std.ArrayList([]const u8),

pub fn init(alloc: Allocator) Editor {
    return .{
        .alloc = alloc,
        .console_lines = .empty,
    };
}

pub fn deinit(self: *Editor) void {
    if (self.initialized) {
        simgui.shutdown();
    }
    self.console_lines.deinit(self.alloc);
}

/// Called once after sokol-gfx is initialized
pub fn setup(self: *Editor) void {
    simgui.setup(.{
        .logger = .{ .func = sokol.log.func },
    });
    self.initialized = true;
}

/// Connect the editor to the game world for inspection
pub fn setWorld(self: *Editor, world: *World) void {
    self.world = world;
}

pub fn log(self: *Editor, msg: []const u8) void {
    self.console_lines.append(self.alloc, msg) catch {};
}

/// Begin a new ImGui frame - call before render()
pub fn beginFrame(self: *Editor) void {
    _ = self;
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });
}

/// Render all editor UI
pub fn render(self: *Editor) void {
    self.renderMainMenuBar();

    if (self.show_scene_view) self.renderSceneView();
    if (self.show_hierarchy) self.renderHierarchy();
    if (self.show_inspector) self.renderInspector();
    if (self.show_console) self.renderConsole();
}

/// Draw ImGui - call after sg.beginPass
pub fn draw(_: *Editor) void {
    simgui.render();
}

/// Forward sokol events to ImGui
pub fn handleEvent(_: *Editor, event: [*c]const sapp.Event) bool {
    return simgui.handleEvent(event.*);
}

// ============================================================================
// Main Menu Bar
// ============================================================================

fn renderMainMenuBar(self: *Editor) void {
    if (ig.igBeginMainMenuBar()) {
        if (ig.igBeginMenu("File")) {
            if (ig.igMenuItem("New Scene")) {
                self.log("New scene created");
            }
            if (ig.igMenuItem("Open Scene...")) {
                self.log("Open scene dialog");
            }
            if (ig.igMenuItem("Save Scene")) {
                self.log("Scene saved");
            }
            ig.igSeparator();
            if (ig.igMenuItem("Exit")) {
                sapp.requestQuit();
            }
            ig.igEndMenu();
        }

        if (ig.igBeginMenu("Edit")) {
            if (ig.igMenuItem("Undo")) {}
            if (ig.igMenuItem("Redo")) {}
            ig.igEndMenu();
        }

        if (ig.igBeginMenu("View")) {
            _ = ig.igMenuItemBoolPtr("Scene View", null, &self.show_scene_view, true);
            _ = ig.igMenuItemBoolPtr("Hierarchy", null, &self.show_hierarchy, true);
            _ = ig.igMenuItemBoolPtr("Inspector", null, &self.show_inspector, true);
            _ = ig.igMenuItemBoolPtr("Console", null, &self.show_console, true);
            ig.igEndMenu();
        }

        if (ig.igBeginMenu("Help")) {
            if (ig.igMenuItem("About Zixel")) {}
            ig.igEndMenu();
        }

        ig.igEndMainMenuBar();
    }
}

// ============================================================================
// Scene View Panel
// ============================================================================

fn renderSceneView(self: *Editor) void {
    ig.igSetNextWindowPos(.{ .x = 250, .y = 30 }, ig.ImGuiCond_FirstUseEver);
    ig.igSetNextWindowSize(.{ .x = 800, .y = 500 }, ig.ImGuiCond_FirstUseEver);

    if (ig.igBegin("Scene", &self.show_scene_view, 0)) {
        const size = ig.igGetContentRegionAvail();

        ig.igText("Scene Viewport");
        ig.igText("Size: %.0f x %.0f", size.x, size.y);
        ig.igSeparator();
        ig.igTextColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "Game world renders here...");

        ig.igSeparator();
        if (ig.igButton("Play")) {
            self.log("Play mode started");
        }
        ig.igSameLine();
        if (ig.igButton("Pause")) {
            self.log("Paused");
        }
        ig.igSameLine();
        if (ig.igButton("Stop")) {
            self.log("Stopped");
        }
    }
    ig.igEnd();
}

// ============================================================================
// Hierarchy Panel - shows bodies from the physics world
// ============================================================================

fn renderHierarchy(self: *Editor) void {
    ig.igSetNextWindowPos(.{ .x = 10, .y = 30 }, ig.ImGuiCond_FirstUseEver);
    ig.igSetNextWindowSize(.{ .x = 230, .y = 300 }, ig.ImGuiCond_FirstUseEver);

    if (ig.igBegin("Hierarchy", &self.show_hierarchy, 0)) {
        if (self.world) |world| {
            // Show actual bodies from the physics world
            var count: usize = 0;
            for (world.slots.items, 0..) |slot, i| {
                if (!slot.alive) continue;

                var buf: [64]u8 = undefined;
                const label = std.fmt.bufPrint(&buf, "Body {d}\x00", .{i}) catch "Body\x00";

                const is_selected = self.selected_entity != null and self.selected_entity.? == i;

                if (ig.igSelectable(label.ptr)) {
                    self.selected_entity = i;
                }
                // Show selection highlight
                if (is_selected) {
                    ig.igText("  <-- selected");
                }
                count += 1;
            }

            if (count == 0) {
                ig.igTextColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "No bodies in world");
            }
        } else {
            ig.igTextColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "No world connected");
        }
    }
    ig.igEnd();
}

// ============================================================================
// Inspector Panel - properties of selected body
// ============================================================================

fn renderInspector(self: *Editor) void {
    ig.igSetNextWindowPos(.{ .x = 1060, .y = 30 }, ig.ImGuiCond_FirstUseEver);
    ig.igSetNextWindowSize(.{ .x = 300, .y = 400 }, ig.ImGuiCond_FirstUseEver);

    if (ig.igBegin("Inspector", &self.show_inspector, 0)) {
        if (self.selected_entity) |idx| {
            if (self.world) |world| {
                if (idx < world.slots.items.len and world.slots.items[idx].alive) {
                    const body = &world.slots.items[idx].body;

                    ig.igText("Body %d", @as(c_int, @intCast(idx)));
                    ig.igSeparator();

                    // Transform section
                    if (ig.igCollapsingHeader("Transform", ig.ImGuiTreeNodeFlags_DefaultOpen)) {
                        ig.igText("Position: %.1f, %.1f", body.position.x, body.position.y);
                        ig.igText("Rotation: %.3f", body.rotation);
                    }

                    // Physics section
                    if (ig.igCollapsingHeader("Physics", ig.ImGuiTreeNodeFlags_DefaultOpen)) {
                        const kind_str: [*c]const u8 = switch (body.kind) {
                            .static => "Static",
                            .dynamic => "Dynamic",
                            .kinematic => "Kinematic",
                        };
                        ig.igText("Kind: %s", kind_str);
                        ig.igText("Mass: %.1f", body.mass);
                        ig.igText("Restitution: %.2f", body.restitution);
                        ig.igText("Friction: %.2f", body.friction);

                        ig.igSeparator();
                        ig.igText("Velocity: %.1f, %.1f", body.velocity.x, body.velocity.y);
                        ig.igText("Angular Vel: %.3f", body.angular_velocity);
                    }
                } else {
                    self.selected_entity = null;
                }
            }
        } else {
            ig.igTextColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "No body selected");
        }
    }
    ig.igEnd();
}

// ============================================================================
// Console Panel
// ============================================================================

fn renderConsole(self: *Editor) void {
    ig.igSetNextWindowPos(.{ .x = 10, .y = 540 }, ig.ImGuiCond_FirstUseEver);
    ig.igSetNextWindowSize(.{ .x = 600, .y = 200 }, ig.ImGuiCond_FirstUseEver);

    if (ig.igBegin("Console", &self.show_console, 0)) {
        if (ig.igButton("Clear")) {
            self.console_lines.clearRetainingCapacity();
        }

        ig.igSeparator();

        // Simple text output (no child window to avoid API issues)
        for (self.console_lines.items) |line| {
            ig.igText("%s", line.ptr);
        }
    }
    ig.igEnd();
}
