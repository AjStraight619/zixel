const std = @import("std");
const World = @import("../physics/World.zig");
const Renderer = @import("Renderer.zig");

const Allocator = std.mem.Allocator;

pub const Renderable = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    render: *const fn (ctx: *anyopaque, world: *World, renderer: *Renderer) void,
    deinit: *const fn (ctx: *anyopaque, alloc: Allocator) void,
};

pub inline fn render(self: Renderable, world: *World, renderer: *Renderer) void {
    self.vtable.render(self.ptr, world, renderer);
}

pub inline fn deinit(self: Renderable, alloc: Allocator) void {
    self.vtable.deinit(self.ptr, alloc);
}

pub fn init(ptr: anytype) Renderable {
    const info = @typeInfo(@TypeOf(ptr));
    if (info != .pointer or info.pointer.size != .one)
        @compileError("Renderable.init expects a *T pointer");

    const T = info.pointer.child;

    comptime {
        if (!@hasDecl(T, "render")) {
            @compileError("Renderable type must have pub fn render(self: *T, world: *World, renderer: *Renderer) void");
        }
        if (!@hasDecl(T, "deinit")) {
            @compileError("Renderable type must have pub fn deinit(self: *T, alloc: Allocator) void");
        }
    }

    return .{
        .ptr = @ptrCast(ptr),
        .vtable = vtableFor(T),
    };
}

fn vtableFor(comptime T: type) *const VTable {
    const Impl = struct {
        fn vRender(ctx: *anyopaque, world: *World, renderer: *Renderer) void {
            const self: *T = @ptrCast(@alignCast(ctx));
            T.render(self, world, renderer);
        }

        fn vDeinit(ctx: *anyopaque, alloc: Allocator) void {
            const self: *T = @ptrCast(@alignCast(ctx));
            T.deinit(self, alloc);
        }

        pub const vtable = VTable{
            .render = vRender,
            .deinit = vDeinit,
        };
    };

    return &Impl.vtable;
}
