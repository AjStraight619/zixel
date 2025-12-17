const std = @import("std");
const Allocator = std.mem.Allocator;

const sokol = @import("sokol");
const sapp = sokol.app;
const simgui = sokol.imgui;

// Import cimgui directly
const ig = @import("cimgui");

const Editor = @This();

alloc: Allocator,

// Panel visibility
show_scene_view: bool = true,
show_hierarchy: bool = true,
show_inspector: bool = true,
show_console: bool = true,

// Selection state
selected_entity: ?usize = null,

// Console log
console_lines: std.ArrayList([]const u8) = .empty,

pub fn init(alloc: Allocator) Editor {
    return .{
        .alloc = alloc,
        .console_lines = .empty,
    };
}

pub fn deinit(self: *Editor) void {
    self.console_lines.deinit(self.alloc);
}

pub fn log(self: *Editor, msg: []const u8) void {
    self.console_lines.append(self.alloc, msg) catch {};
}

pub fn render(self: *Editor) void {
    self.renderMainMenuBar();

    if (self.show_scene_view) self.renderSceneView();
    if (self.show_hierarchy) self.renderHierarchy();
    if (self.show_inspector) self.renderInspector();
    if (self.show_console) self.renderConsole();
}

pub fn handleEvent(self: *Editor, event: [*c]const sapp.Event) void {
    _ = self;
    _ = event;
}

// ============================================================================
// Main Menu Bar
// ============================================================================

fn renderMainMenuBar(self: *Editor) void {
    if (ig.igBeginMainMenuBar()) {
        if (ig.igBeginMenuEx("File", true)) {
            if (ig.igMenuItemEx("New Scene", "Ctrl+N", false, true)) {
                self.log("New scene created");
            }
            if (ig.igMenuItemEx("Open Scene...", "Ctrl+O", false, true)) {
                self.log("Open scene dialog");
            }
            if (ig.igMenuItemEx("Save Scene", "Ctrl+S", false, true)) {
                self.log("Scene saved");
            }
            ig.igSeparator();
            if (ig.igMenuItemEx("Exit", "Alt+F4", false, true)) {
                sapp.requestQuit();
            }
            ig.igEndMenu();
        }

        if (ig.igBeginMenuEx("Edit", true)) {
            if (ig.igMenuItemEx("Undo", "Ctrl+Z", false, true)) {}
            if (ig.igMenuItemEx("Redo", "Ctrl+Y", false, true)) {}
            ig.igEndMenu();
        }

        if (ig.igBeginMenuEx("View", true)) {
            _ = ig.igMenuItemBoolPtr("Scene View", null, &self.show_scene_view, true);
            _ = ig.igMenuItemBoolPtr("Hierarchy", null, &self.show_hierarchy, true);
            _ = ig.igMenuItemBoolPtr("Inspector", null, &self.show_inspector, true);
            _ = ig.igMenuItemBoolPtr("Console", null, &self.show_console, true);
            ig.igEndMenu();
        }

        if (ig.igBeginMenuEx("Help", true)) {
            if (ig.igMenuItem("About Zixel")) {}
            ig.igEndMenu();
        }

        ig.igEndMainMenuBar();
    }
}

// ============================================================================
// Scene View Panel - renders the game world
// ============================================================================

fn renderSceneView(self: *Editor) void {
    ig.igSetNextWindowPos(.{ .x = 250, .y = 30 }, ig.ImGuiCond_FirstUseEver);
    ig.igSetNextWindowSize(.{ .x = 800, .y = 500 }, ig.ImGuiCond_FirstUseEver);

    if (ig.igBegin("Scene", &self.show_scene_view, ig.ImGuiWindowFlags_None)) {
        const size = ig.igGetContentRegionAvail();

        ig.igText("Scene Viewport");
        ig.igText("Size: %.0f x %.0f", size.x, size.y);
        ig.igSeparator();
        ig.igTextColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "Game world renders here...");

        ig.igSeparator();
        if (ig.igButton("Play")) {
            self.log("Play mode started");
        }
        ig.igSameLineEx(0, 5);
        if (ig.igButton("Pause")) {
            self.log("Paused");
        }
        ig.igSameLineEx(0, 5);
        if (ig.igButton("Stop")) {
            self.log("Stopped");
        }
    }
    ig.igEnd();
}

// ============================================================================
// Hierarchy Panel - tree of entities in the scene
// ============================================================================

fn renderHierarchy(self: *Editor) void {
    ig.igSetNextWindowPos(.{ .x = 10, .y = 30 }, ig.ImGuiCond_FirstUseEver);
    ig.igSetNextWindowSize(.{ .x = 230, .y = 300 }, ig.ImGuiCond_FirstUseEver);

    if (ig.igBegin("Hierarchy", &self.show_hierarchy, ig.ImGuiWindowFlags_None)) {
        const entities = [_][]const u8{
            "Player",
            "Enemy_01",
            "Enemy_02",
            "Ground",
            "Platform_01",
            "Camera",
        };

        for (entities, 0..) |name, i| {
            const is_selected = self.selected_entity != null and self.selected_entity.? == i;
            const flags: ig.ImGuiTreeNodeFlags = ig.ImGuiTreeNodeFlags_Leaf |
                ig.ImGuiTreeNodeFlags_NoTreePushOnOpen |
                (if (is_selected) ig.ImGuiTreeNodeFlags_Selected else 0);

            _ = ig.igTreeNodeEx(name.ptr, flags);

            if (ig.igIsItemClickedEx(ig.ImGuiMouseButton_Left)) {
                self.selected_entity = i;
            }
        }
    }
    ig.igEnd();
}

// ============================================================================
// Inspector Panel - properties of selected entity
// ============================================================================

fn renderInspector(self: *Editor) void {
    ig.igSetNextWindowPos(.{ .x = 1060, .y = 30 }, ig.ImGuiCond_FirstUseEver);
    ig.igSetNextWindowSize(.{ .x = 300, .y = 400 }, ig.ImGuiCond_FirstUseEver);

    if (ig.igBegin("Inspector", &self.show_inspector, ig.ImGuiWindowFlags_None)) {
        if (self.selected_entity) |_| {
            ig.igText("Entity Properties");
            ig.igSeparator();

            // Transform section
            if (ig.igCollapsingHeader("Transform", ig.ImGuiTreeNodeFlags_DefaultOpen)) {
                var pos = [2]f32{ 100.0, 200.0 };
                var rot: f32 = 0.0;
                var scale = [2]f32{ 1.0, 1.0 };

                _ = ig.igDragFloat2Ex("Position", &pos, 1.0, -10000, 10000, "%.1f", 0);
                _ = ig.igDragFloatEx("Rotation", &rot, 1.0, -360, 360, "%.1f", 0);
                _ = ig.igDragFloat2Ex("Scale", &scale, 0.01, 0.01, 100, "%.2f", 0);
            }

            // Physics section
            if (ig.igCollapsingHeader("Physics Body", ig.ImGuiTreeNodeFlags_DefaultOpen)) {
                var mass: f32 = 1.0;
                var is_static = false;

                _ = ig.igDragFloatEx("Mass", &mass, 0.1, 0.0, 1000, "%.1f", 0);
                _ = ig.igCheckbox("Static", &is_static);
            }

            // Renderer section
            if (ig.igCollapsingHeader("Sprite Renderer", ig.ImGuiTreeNodeFlags_DefaultOpen)) {
                var color = [4]f32{ 1.0, 1.0, 1.0, 1.0 };
                _ = ig.igColorEdit4("Color", &color, 0);
            }
        } else {
            ig.igTextColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "No entity selected");
        }
    }
    ig.igEnd();
}

// ============================================================================
// Console Panel - log output
// ============================================================================

fn renderConsole(self: *Editor) void {
    ig.igSetNextWindowPos(.{ .x = 10, .y = 540 }, ig.ImGuiCond_FirstUseEver);
    ig.igSetNextWindowSize(.{ .x = 600, .y = 200 }, ig.ImGuiCond_FirstUseEver);

    if (ig.igBegin("Console", &self.show_console, ig.ImGuiWindowFlags_None)) {
        if (ig.igButton("Clear")) {
            self.console_lines.clearRetainingCapacity();
        }

        ig.igSeparator();

        if (ig.igBeginChild("ConsoleScroll", .{ .x = 0, .y = 0 }, ig.ImGuiChildFlags_None, ig.ImGuiWindowFlags_HorizontalScrollbar)) {
            for (self.console_lines.items) |line| {
                ig.igTextUnformatted(line.ptr);
            }

            if (ig.igGetScrollY() >= ig.igGetScrollMaxY()) {
                ig.igSetScrollHereY(1.0);
            }
        }
        ig.igEndChild();
    }
    ig.igEnd();
}
