const std = @import("std");
const rl = @import("raylib");
const Vector2 = rl.Vector2;
const Rectangle = rl.Rectangle;
const Color = rl.Color;
const PhysicsBodyType = @import("../physics/body.zig").Body;
const PhysicsWorld = @import("../physics/world.zig").PhysicsWorld;

// ============================================================================
// CORE COMPONENTS
// ============================================================================

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

// ============================================================================
// PHYSICS COMPONENTS
// ============================================================================

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

/// Legacy RigidBody - now deprecated in favor of PhysicsBodyRef
pub const RigidBody = struct {
    pub const BodyType = enum {
        Static, // Cannot move, infinite mass
        Kinematic, // Moves but not affected by forces
        Dynamic, // Full physics simulation
    };

    body_type: BodyType = .Dynamic,
    mass: f32 = 1.0,
    gravity_scale: f32 = 1.0,
    linear_damping: f32 = 0.0,
    angular_damping: f32 = 0.0,
    is_active: bool = true,

    // NOTE: This is now deprecated - use PhysicsBodyRef instead
    // This is kept for backwards compatibility only
};

/// Collision shape definitions
pub const Collider = struct {
    pub const ColliderShape = union(enum) {
        Circle: struct {
            radius: f32,
        },
        Rectangle: struct {
            width: f32,
            height: f32,
        },
        Capsule: struct {
            radius: f32,
            height: f32,
        },
    };

    shape: ColliderShape,
    /// Offset from entity position
    offset: Vector2 = Vector2.init(0, 0),
    /// Whether this collider triggers events (no physical response)
    is_trigger: bool = false,
    /// Collision layers this collider belongs to
    layer: u32 = 1,
    /// Collision mask - which layers this collider interacts with
    mask: u32 = 0xFFFFFFFF,

    pub fn circle(radius: f32) Collider {
        return Collider{
            .shape = .{ .Circle = .{ .radius = radius } },
        };
    }

    pub fn rectangle(width: f32, height: f32) Collider {
        return Collider{
            .shape = .{ .Rectangle = .{ .width = width, .height = height } },
        };
    }

    pub fn capsule(radius: f32, height: f32) Collider {
        return Collider{
            .shape = .{ .Capsule = .{ .radius = radius, .height = height } },
        };
    }

    pub fn getBounds(self: *const Collider, transform: Transform) rl.Rectangle {
        const pos = rl.Vector2.init(transform.position.x + self.offset.x, transform.position.y + self.offset.y);

        return switch (self.shape) {
            .Circle => |circle_shape| .{
                .x = pos.x - circle_shape.radius,
                .y = pos.y - circle_shape.radius,
                .width = circle_shape.radius * 2,
                .height = circle_shape.radius * 2,
            },
            .Rectangle => |rect_shape| .{
                .x = pos.x - rect_shape.width / 2,
                .y = pos.y - rect_shape.height / 2,
                .width = rect_shape.width,
                .height = rect_shape.height,
            },
            .Capsule => |capsule_shape| .{
                .x = pos.x - capsule_shape.radius,
                .y = pos.y - capsule_shape.height / 2,
                .width = capsule_shape.radius * 2,
                .height = capsule_shape.height,
            },
        };
    }
};

// ============================================================================
// RENDERING COMPONENTS
// ============================================================================

/// 2D sprite rendering
pub const Sprite = struct {
    /// Texture handle/ID (0 = use color only)
    texture_id: u32 = 0,
    /// Source rectangle in texture (null = full texture)
    source_rect: ?rl.Rectangle = null,
    /// Tint color
    color: Color = Color.white,
    /// Render layer (higher = rendered on top)
    layer: i32 = 0,
    /// Whether sprite should flip horizontally
    flip_x: bool = false,
    /// Whether sprite should flip vertically
    flip_y: bool = false,
    /// Sprite anchor point (0,0 = top-left, 0.5,0.5 = center)
    anchor: Vector2 = Vector2.init(0.5, 0.5),

    pub fn fromColor(color: Color) Sprite {
        return Sprite{
            .color = color,
        };
    }

    pub fn fromTexture(texture_id: u32) Sprite {
        return Sprite{
            .texture_id = texture_id,
        };
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

// ============================================================================
// GAMEPLAY COMPONENTS
// ============================================================================

/// Player controller component
pub const Player = struct {
    player_id: u8 = 0,
    move_speed: f32 = 100.0,
    jump_force: f32 = 300.0,
    is_grounded: bool = false,
    can_double_jump: bool = false,
    has_used_double_jump: bool = false,
};

/// AI behavior component
pub const AI = struct {
    pub const BehaviorType = enum {
        None,
        FollowPlayer,
        Patrol,
        GuardArea,
        Flee,
        Aggressive,
    };

    behavior: BehaviorType = .None,
    target_entity: ?u64 = null,
    patrol_points: [4]Vector2 = [_]Vector2{Vector2.init(0, 0)} ** 4,
    patrol_index: u8 = 0,
    detection_radius: f32 = 100.0,
    move_speed: f32 = 50.0,
    last_seen_position: Vector2 = Vector2.init(0, 0),
};

/// Health and damage system
pub const Health = struct {
    current: f32,
    max: f32,
    regeneration_rate: f32 = 0.0,
    is_invulnerable: bool = false,
    invulnerability_timer: f32 = 0.0,

    pub fn init(max_health: f32) Health {
        return Health{
            .current = max_health,
            .max = max_health,
        };
    }

    pub fn damage(self: *Health, amount: f32) void {
        if (self.is_invulnerable) return;
        self.current = @max(0, self.current - amount);
    }

    pub fn heal(self: *Health, amount: f32) void {
        self.current = @min(self.max, self.current + amount);
    }

    pub fn isDead(self: *const Health) bool {
        return self.current <= 0;
    }

    pub fn getHealthPercentage(self: *const Health) f32 {
        return self.current / self.max;
    }
};

/// Timer component for various time-based behaviors
pub const Timer = struct {
    remaining: f32,
    duration: f32,
    is_repeating: bool = false,
    is_paused: bool = false,

    pub fn init(duration: f32) Timer {
        return Timer{
            .remaining = duration,
            .duration = duration,
        };
    }

    pub fn repeating(duration: f32) Timer {
        return Timer{
            .remaining = duration,
            .duration = duration,
            .is_repeating = true,
        };
    }

    pub fn update(self: *Timer, dt: f32) bool {
        if (self.is_paused) return false;

        self.remaining -= dt;

        if (self.remaining <= 0) {
            if (self.is_repeating) {
                self.remaining = self.duration;
            }
            return true; // Timer finished
        }

        return false;
    }

    pub fn reset(self: *Timer) void {
        self.remaining = self.duration;
    }

    pub fn getProgress(self: *const Timer) f32 {
        return 1.0 - (self.remaining / self.duration);
    }
};

/// Lifetime component - entity despawns when timer expires
pub const Lifetime = struct {
    remaining: f32,

    pub fn init(duration: f32) Lifetime {
        return Lifetime{
            .remaining = duration,
        };
    }

    pub fn update(self: *Lifetime, dt: f32) bool {
        self.remaining -= dt;
        return self.remaining <= 0;
    }
};

/// Animation component for sprite animation
pub const Animation = struct {
    /// Current frame index
    current_frame: u32 = 0,
    /// Total number of frames
    frame_count: u32,
    /// Frames per second
    fps: f32,
    /// Time since last frame change
    frame_timer: f32 = 0.0,
    /// Whether animation loops
    is_looping: bool = true,
    /// Whether animation is playing
    is_playing: bool = true,
    /// Animation name/ID
    animation_id: u32 = 0,

    pub fn init(frame_count: u32, fps: f32) Animation {
        return Animation{
            .frame_count = frame_count,
            .fps = fps,
        };
    }

    pub fn update(self: *Animation, dt: f32) bool {
        if (!self.is_playing) return false;

        self.frame_timer += dt;
        const frame_duration = 1.0 / self.fps;

        if (self.frame_timer >= frame_duration) {
            self.frame_timer -= frame_duration;
            self.current_frame += 1;

            if (self.current_frame >= self.frame_count) {
                if (self.is_looping) {
                    self.current_frame = 0;
                } else {
                    self.current_frame = self.frame_count - 1;
                    self.is_playing = false;
                    return true; // Animation finished
                }
            }
        }

        return false;
    }

    pub fn play(self: *Animation) void {
        self.is_playing = true;
    }

    pub fn pause(self: *Animation) void {
        self.is_playing = false;
    }

    pub fn reset(self: *Animation) void {
        self.current_frame = 0;
        self.frame_timer = 0.0;
        self.is_playing = true;
    }
};

// ============================================================================
// AUDIO COMPONENTS
// ============================================================================

/// Audio source component
pub const AudioSource = struct {
    /// Audio clip ID
    clip_id: u32,
    /// Volume (0.0 to 1.0)
    volume: f32 = 1.0,
    /// Pitch multiplier
    pitch: f32 = 1.0,
    /// Whether audio loops
    is_looping: bool = false,
    /// Whether this is 3D positional audio
    is_3d: bool = false,
    /// Whether audio is currently playing
    is_playing: bool = false,
    /// Whether to play on awake
    play_on_awake: bool = false,

    pub fn init(clip_id: u32) AudioSource {
        return AudioSource{
            .clip_id = clip_id,
        };
    }

    pub fn music(clip_id: u32) AudioSource {
        return AudioSource{
            .clip_id = clip_id,
            .is_looping = true,
            .play_on_awake = true,
        };
    }

    pub fn sfx(clip_id: u32) AudioSource {
        return AudioSource{
            .clip_id = clip_id,
            .is_3d = true,
        };
    }
};

// ============================================================================
// INPUT COMPONENTS
// ============================================================================

/// Input handling component
pub const Input = struct {
    /// Movement input vector
    movement: Vector2 = Vector2.init(0, 0),
    /// Action buttons pressed this frame
    actions: u32 = 0,
    /// Action buttons held
    actions_held: u32 = 0,
    /// Mouse position in world space
    mouse_world_pos: Vector2 = Vector2.init(0, 0),
    /// Mouse buttons pressed this frame
    mouse_buttons: u8 = 0,
    /// Mouse buttons held
    mouse_buttons_held: u8 = 0,

    pub const Action = enum(u5) {
        Jump = 0,
        Attack = 1,
        Interact = 2,
        Menu = 3,
        Inventory = 4,
        // Add more actions as needed
    };

    pub fn isActionPressed(self: *const Input, action: Action) bool {
        const bit = @as(u32, 1) << @intFromEnum(action);
        return (self.actions & bit) != 0;
    }

    pub fn isActionHeld(self: *const Input, action: Action) bool {
        const bit = @as(u32, 1) << @intFromEnum(action);
        return (self.actions_held & bit) != 0;
    }

    pub fn setAction(self: *Input, action: Action, pressed: bool, held: bool) void {
        const bit = @as(u32, 1) << @intFromEnum(action);
        if (pressed) {
            self.actions |= bit;
        } else {
            self.actions &= ~bit;
        }

        if (held) {
            self.actions_held |= bit;
        } else {
            self.actions_held &= ~bit;
        }
    }
};

// ============================================================================
// UTILITY COMPONENTS
// ============================================================================

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
