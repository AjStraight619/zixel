const std = @import("std");
const rl = @import("raylib");
const Vector2 = rl.Vector2;
const Rectangle = rl.Rectangle;
const Color = rl.Color;
const PhysicsBodyType = @import("../physics/body.zig").Body;
const PhysicsWorld = @import("../physics/world.zig").PhysicsWorld;

pub const ComponentType = enum(u32) {
    Transform,
    Velocity,
    PhysicsBodyRef,
    Shape,
    Text,
    Tag,
    ToDestroy,
    Camera2D,
    Input,

    pub fn getId(comptime T: type) ComponentType {
        return switch (T) {
            Transform => .Transform,
            Velocity => .Velocity,
            PhysicsBodyRef => .PhysicsBodyRef,
            Shape => .Shape,
            Text => .Text,
            Tag => .Tag,
            ToDestroy => .ToDestroy,
            Camera2D => .Camera2D,
            Input => .Input,
            else => @compileError("Component not registered: " ++ @typeName(T)),
        };
    }

    pub fn toU32(self: ComponentType) u32 {
        return @intFromEnum(self);
    }
};

/// Position and transformation in 2D space
pub const Transform = struct {
    position: Vector2 = Vector2.init(0, 0),
    rotation: f32 = 0.0, // Radians
    scale: Vector2 = Vector2.init(1, 1),

    pub fn forward(self: *const Transform) Vector2 {
        return Vector2.init(@cos(self.rotation), @sin(self.rotation));
    }

    pub fn right(self: *const Transform) Vector2 {
        return Vector2.init(@cos(self.rotation + std.math.pi / 2.0), @sin(self.rotation + std.math.pi / 2.0));
    }

    pub fn translate(self: *Transform, offset: Vector2) void {
        self.position.x += offset.x;
        self.position.y += offset.y;
    }

    pub fn rotate(self: *Transform, angle: f32) void {
        self.rotation += angle;
    }
};

/// Hierarchical parent-child relationships
pub const Parent = struct {
    entity: u64,
};

pub const Child = struct {
    entity: u64,
};

/// Name/identifier for entities
pub const Name = struct {
    value: [64]u8 = [_]u8{0} ** 64,

    pub fn set(self: *Name, name: []const u8) void {
        const len = @min(name.len, 63);
        @memcpy(self.value[0..len], name[0..len]);
        self.value[len] = 0;
    }

    pub fn get(self: *const Name) []const u8 {
        const end = std.mem.indexOfScalar(u8, &self.value, 0) orelse self.value.len;
        return self.value[0..end];
    }
};

/// Velocity and acceleration for movement
pub const Velocity = struct {
    linear: Vector2 = Vector2.init(0, 0),
    angular: f32 = 0.0, // Radians per second

    pub fn zero() Velocity {
        return Velocity{};
    }

    pub fn addForce(self: *Velocity, force: Vector2, mass: f32) void {
        const acceleration = Vector2.init(force.x / mass, force.y / mass);
        self.linear.x += acceleration.x;
        self.linear.y += acceleration.y;
    }
};

/// References a body in the physics world for proper physics simulation
pub const PhysicsBodyRef = struct {
    body_id: usize, // Index into the physics world's body array

    pub fn init(body_id: usize) PhysicsBodyRef {
        return PhysicsBodyRef{
            .body_id = body_id,
        };
    }

    /// Get the physics body from the world (helper function)
    pub fn getBody(self: PhysicsBodyRef, physics_world: *PhysicsWorld) ?*PhysicsBodyType {
        return physics_world.getBody(self.body_id);
    }

    /// Sync transform component with physics body position
    pub fn syncToTransform(self: PhysicsBodyRef, physics_world: *PhysicsWorld, transform: *Transform) void {
        if (physics_world.getBody(self.body_id)) |body| {
            transform.position = body.getPosition();
            transform.rotation = body.getRotation();
        }
    }

    /// Update physics body from transform (for kinematic control)
    pub fn syncFromTransform(self: PhysicsBodyRef, physics_world: *PhysicsWorld, transform: *const Transform) void {
        if (physics_world.getBody(self.body_id)) |body| {
            // This would require setPosition/setRotation methods on Body
            // For now, we'll let physics drive the transform
            _ = body;
            _ = transform;
        }
    }
};

/// Shape rendering (circles, rectangles, lines)
pub const Shape = struct {
    pub const ShapeType = union(enum) {
        Circle: struct {
            radius: f32,
            filled: bool = true,
        },
        Rectangle: struct {
            width: f32,
            height: f32,
            filled: bool = true,
        },
        Line: struct {
            end_pos: Vector2,
            thickness: f32 = 1.0,
        },
    };

    shape_type: ShapeType,
    color: Color = Color.white,
    layer: i32 = 0,

    pub fn circle(radius: f32, filled: bool) Shape {
        return Shape{
            .shape_type = .{ .Circle = .{ .radius = radius, .filled = filled } },
        };
    }

    pub fn rectangle(width: f32, height: f32, filled: bool) Shape {
        return Shape{
            .shape_type = .{ .Rectangle = .{ .width = width, .height = height, .filled = filled } },
        };
    }

    pub fn line(end_pos: Vector2, thickness: f32) Shape {
        return Shape{
            .shape_type = .{ .Line = .{ .end_pos = end_pos, .thickness = thickness } },
        };
    }
};

/// Text rendering
pub const Text = struct {
    content: [256]u8 = [_]u8{0} ** 256,
    font_size: f32 = 20.0,
    color: Color = Color.black,
    /// Font ID (0 = default font)
    font_id: u32 = 0,
    layer: i32 = 10, // Text usually on top

    pub fn setText(self: *Text, text: []const u8) void {
        const len = @min(text.len, 255);
        @memcpy(self.content[0..len], text[0..len]);
        self.content[len] = 0;
    }

    pub fn getText(self: *const Text) []const u8 {
        const end = std.mem.indexOfScalar(u8, &self.content, 0) orelse self.content.len;
        return self.content[0..end];
    }
};

/// Tag component for various entity classifications
pub const Tag = struct {
    pub const TagType = enum {
        Player,
        Enemy,
        Projectile,
        Collectible,
        Platform,
        Trigger,
        UI,
        Background,
        Foreground,
        Obstacle,
    };

    tags: u32 = 0,

    pub fn add(self: *Tag, tag: TagType) void {
        const bit = @as(u32, 1) << @intFromEnum(tag);
        self.tags |= bit;
    }

    pub fn remove(self: *Tag, tag: TagType) void {
        const bit = @as(u32, 1) << @intFromEnum(tag);
        self.tags &= ~bit;
    }

    pub fn has(self: *const Tag, tag: TagType) bool {
        const bit = @as(u32, 1) << @intFromEnum(tag);
        return (self.tags & bit) != 0;
    }
};

/// Component for entities that should be removed
pub const ToDestroy = struct {
    // Empty marker component
};

/// Camera for 2D rendering
pub const Camera2D = struct {
    /// Camera target (what it's looking at)
    target: Vector2 = Vector2.init(0, 0),
    /// Camera offset from target
    offset: Vector2 = Vector2.init(0, 0),
    /// Camera zoom level
    zoom: f32 = 1.0,
    /// Camera rotation in radians
    rotation: f32 = 0.0,
    /// Whether this is the main camera
    is_main: bool = false,

    pub fn main(target: Vector2) Camera2D {
        return Camera2D{
            .target = target,
            .is_main = true,
        };
    }

    pub fn followEntity(target: Vector2, offset: Vector2) Camera2D {
        return Camera2D{
            .target = target,
            .offset = offset,
        };
    }
};

pub const Input = struct {
    // Input state
    move_left: bool = false,
    move_right: bool = false,
    move_up: bool = false,
    move_down: bool = false,
    jump: bool = false,

    // Settings
    move_speed: f32 = 200.0,
    jump_force: f32 = 300.0,

    // Jump buffering
    jump_buffer_time: f32 = 0.0,
    jump_buffer_max: f32 = 0.1,
};
