const std = @import("std");
const math = std.math;

const Vec2 = @import("../math/vec2.zig");
const Body = @import("body.zig").Body;
const ContactManifold = @import("narrowphase.zig").ContactManifold;

// Small thresholds to avoid doing tiny useless corrections (micro-jitter).
const TANGENT_EPS: f32 = 1e-6;
const TANGENT_DEADZONE: f32 = 1e-4;

/// We calculate this ONCE per body per collision to avoid repeated lookups.
const SolverData = struct {
    inv_mass: f32,
    inv_inertia: f32,
    r: Vec2, // The lever arm (vector from center of body to contact point)

    /// Calculates "Effective Inverse Mass" (K) along a specific direction.
    /// This represents how much velocity a point on the body gains when pushed.
    /// Formula: K = (1/Mass) + (LeverArm_Perpendicular^2 / Inertia)
    fn getEffectiveMass(self: SolverData, dir: Vec2) f32 {
        // The cross product in 2D (r cross dir) is a scalar representing the
        // perpendicular distance from the center of mass to the line of force.
        const rn = self.r.cross2(dir);
        return self.inv_mass + (rn * rn) * self.inv_inertia;
    }
};

/// Helper to build the cache.
fn getSolverData(body: *Body, contact_point: Vec2) SolverData {
    if (body.kind != .dynamic) {
        return .{
            .inv_mass = 0.0,
            .inv_inertia = 0.0,
            .r = Vec2.zero,
        };
    }
    return .{
        .inv_mass = 1.0 / body.mass,
        .inv_inertia = 1.0 / body.inertia,
        .r = contact_point.sub(body.position),
    };
}

/// Entry point for collision response.
/// Handles bounce first, then friction.
pub fn resolveWithMaterials(
    body1: *Body,
    body2: *Body,
    m: ContactManifold,
    restitution1: f32,
    restitution2: f32,
    friction1: f32,
    friction2: f32,
    restitution_clamp_threshold: f32,
) void {
    // 1. Pre-calculate solver data (Mass, Inertia, R-vector)
    const sd1 = getSolverData(body1, m.point);
    const sd2 = getSolverData(body2, m.point);

    // Combine material properties
    const restitution = @sqrt(restitution1 * restitution2);
    const friction = @sqrt(friction1 * friction2);

    // 2. Resolve Bounce (Normal Impulse)
    const res = resolveNormalImpulse(body1, body2, sd1, sd2, m, restitution, restitution_clamp_threshold);

    // 3. Resolve Friction (Tangent Impulse)
    applyFrictionImpulse(body1, body2, sd1, sd2, m, friction, res.jn, res.vrel_before);
}

const NormalImpulseResult = struct {
    jn: f32,
    vrel_before: Vec2,
};

/// Handles bounce along the collision normal.
fn resolveNormalImpulse(
    body1: *Body,
    body2: *Body,
    sd1: SolverData,
    sd2: SolverData,
    m: ContactManifold,
    restitution: f32,
    clamp_threshold: f32,
) NormalImpulseResult {
    // Calculate velocity at the specific contact point for each body
    // Velocity = LinearVel + (AngularVel * R_perp)
    const v1 = if (body1.kind == .dynamic)
        body1.velocity.add(Vec2{ .x = -body1.angular_velocity * sd1.r.y, .y = body1.angular_velocity * sd1.r.x })
    else
        Vec2.zero;

    const v2 = if (body2.kind == .dynamic)
        body2.velocity.add(Vec2{ .x = -body2.angular_velocity * sd2.r.y, .y = body2.angular_velocity * sd2.r.x })
    else
        Vec2.zero;

    // Relative velocity
    const vrel = v2.sub(v1);
    const vn = vrel.dot(m.normal);

    // If bodies are already separating, don't bounce
    if (vn > 0.0) {
        return .{ .jn = 0.0, .vrel_before = vrel };
    }

    // Compute "K" (Total Inverse Effective Mass)
    // This single number tells us how "soft" the system is along the normal.
    const k = sd1.getEffectiveMass(m.normal) + sd2.getEffectiveMass(m.normal);

    // If K is zero, both bodies are static/infinite mass, so we can't do anything.
    if (k <= 0.0) return .{ .jn = 0.0, .vrel_before = vrel };

    // Bias (Restitution) - disable bounce if impact is very slow
    const e = if (@abs(vn) < clamp_threshold) 0.0 else restitution;

    // Calculate impulse magnitude (scalar)
    var jn = -(1.0 + e) * vn / k;
    jn = @min(jn, 1000.0); // Clamp huge impulses for stability

    // Apply the impulse to both bodies
    const impulse_vec = m.normal.scale(jn);
    applyImpulse(body1, sd1, impulse_vec.negate()); // Body 1 pushed opposite
    applyImpulse(body2, sd2, impulse_vec); // Body 2 pushed forward

    return .{ .jn = jn, .vrel_before = vrel };
}

/// Applies friction along the surface tangent.
fn applyFrictionImpulse(
    body1: *Body,
    body2: *Body,
    sd1: SolverData,
    sd2: SolverData,
    m: ContactManifold,
    friction: f32,
    jn: f32,
    vrel_old: Vec2,
) void {
    if (jn == 0.0) return;

    // 1. Calculate the Tangent Vector (Direction of slide)
    const vn = vrel_old.dot(m.normal);
    const tangent = vrel_old.sub(m.normal.scale(vn));

    if (tangent.length() < TANGENT_EPS) return;
    const t_hat = tangent.normalize();

    // 2. Check tangential velocity magnitude
    const vt = vrel_old.dot(t_hat);
    if (@abs(vt) < TANGENT_DEADZONE) return;

    // 3. Compute "K" along the Tangent
    const k = sd1.getEffectiveMass(t_hat) + sd2.getEffectiveMass(t_hat);

    if (k <= 0.0) return;

    // 4. Calculate Friction Impulse
    var jt = -vt / k;

    // Clamp friction using Coulomb's Law: Friction <= NormalForce * coefficient
    const max_jt = friction * @abs(jn);
    jt = math.clamp(jt, -max_jt, max_jt);

    // 5. Apply
    const impulse_vec = t_hat.scale(jt);
    applyImpulse(body1, sd1, impulse_vec.negate());
    applyImpulse(body2, sd2, impulse_vec);
}

/// Internal helper to apply a raw impulse vector to a body using cached data.
fn applyImpulse(body: *Body, sd: SolverData, impulse: Vec2) void {
    if (body.kind != .dynamic) return;

    // Linear: v += impulse / mass
    body.velocity = body.velocity.add(impulse.scale(sd.inv_mass));

    // Angular: w += (r x impulse) / inertia
    body.angular_velocity += sd.r.cross2(impulse) * sd.inv_inertia;
}

/// Push overlapping bodies apart.
/// This does NOT need SolverData because it operates on Position, not Velocity/Inertia.
pub fn correctPositions(
    body1: *Body,
    body2: *Body,
    m: ContactManifold,
    correction_factor: f32,
) void {
    const b1_dyn = body1.kind == .dynamic;
    const b2_dyn = body2.kind == .dynamic;

    if (!b1_dyn and !b2_dyn) return;

    const inv_m1 = if (b1_dyn) 1.0 / body1.mass else 0.0;
    const inv_m2 = if (b2_dyn) 1.0 / body2.mass else 0.0;
    const sum = inv_m1 + inv_m2;

    if (sum <= 0.0) return;

    const corr_mag = (m.penetration / sum) * correction_factor;
    const corr = m.normal.scale(corr_mag);

    if (b1_dyn) body1.position = body1.position.sub(corr.scale(inv_m1));
    if (b2_dyn) body2.position = body2.position.add(corr.scale(inv_m2));
}

const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;

fn makeTestDynamicBody(x: f32, y: f32, size: f32) Body {
    return Body.initDynamic(
        PhysicsShape{ .rectangle = .{ .width = size, .height = size } },
        Vec2.init(x, y),
        .{ .mass = 1.0 },
    );
}

fn makeTestStaticBody(x: f32, y: f32, w: f32, h: f32, rot: f32) Body {
    return Body.initStatic(
        PhysicsShape{ .rectangle = .{ .width = w, .height = h } },
        Vec2.init(x, y),
        .{ .rotation = rot },
    );
}

test "cross2: basic directions" {
    // Right × Up = positive (CCW)
    const right = Vec2.init(1, 0);
    const up = Vec2.init(0, -1); // In screen coords, up is -y
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), right.cross2(up), 0.001);

    // Right × Down = negative (CW)
    const down = Vec2.init(0, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), right.cross2(down), 0.001);
}

test "applyImpulse: center hit causes no rotation" {
    var body = makeTestDynamicBody(100, 100, 40);
    const contact = Vec2.init(100, 100);
    // applyImpulse receives the impulse applied to this body directly.
    applyImpulse(&body, getSolverData(&body, contact), Vec2.init(0, -100));
    try std.testing.expectApproxEqAbs(@as(f32, -100), body.velocity.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), body.angular_velocity, 0.001);
}

test "applyImpulse: upward hit on right side rotates counterclockwise" {
    var body = makeTestDynamicBody(100, 100, 40);
    const contact = Vec2.init(120, 100);
    applyImpulse(&body, getSolverData(&body, contact), Vec2.init(0, -100));
    // r x impulse = 20 * -100, negative rotation in Y-down coordinates.
    try std.testing.expectApproxEqAbs(@as(f32, -100), body.velocity.y, 0.001);
    try std.testing.expectApproxEqAbs(-2000 / body.inertia, body.angular_velocity, 0.001);
}

test "applyImpulse: upward hit on left side rotates clockwise" {
    var body = makeTestDynamicBody(100, 100, 40);
    const contact = Vec2.init(80, 100);
    applyImpulse(&body, getSolverData(&body, contact), Vec2.init(0, -100));
    try std.testing.expectApproxEqAbs(@as(f32, -100), body.velocity.y, 0.001);
    try std.testing.expectApproxEqAbs(2000 / body.inertia, body.angular_velocity, 0.001);
}

test "box falling on flat ground: should not spin" {
    var box = makeTestDynamicBody(100, 80, 40);
    box.velocity = Vec2.init(0, 100); // Falling down

    var ground = makeTestStaticBody(100, 120, 200, 20, 0);

    // Normal convention: points FROM body1 TO body2
    // box is body1, ground is body2
    // So normal should point DOWN (from box toward ground)
    const manifold = ContactManifold.init(
        Vec2.init(100, 100), // Contact point at box bottom center
        Vec2.init(0, 1), // Normal pointing DOWN (from box to ground)
        5.0, // Some penetration
    );

    std.debug.print("\n[TEST] box falling on flat ground:\n", .{});
    std.debug.print("  before: vel=({d:.1}, {d:.1}) ω={d:.3}\n", .{ box.velocity.x, box.velocity.y, box.angular_velocity });

    // vrel = v2 - v1 = 0 - (0, 100) = (0, -100)
    // vn = vrel.dot(normal) = (0, -100).dot(0, 1) = -100 (approaching)
    // jn = -(1+e) * vn / k = -(1.5) * (-100) / k = 150 / k
    // impulse = normal * jn = (0, jn) pushing ground down, box up

    _ = resolveNormalImpulse(&box, &ground, getSolverData(&box, manifold.point), getSolverData(&ground, manifold.point), manifold, 0.5, 3.0);

    std.debug.print("  after:  vel=({d:.1}, {d:.1}) ω={d:.3}\n", .{ box.velocity.x, box.velocity.y, box.angular_velocity });

    // Contact at center = no rotation
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), box.angular_velocity, 0.001);
    // Velocity should reverse (bounce up = negative Y)
    try std.testing.expect(box.velocity.y < 0);
}

test "box sliding down ramp: friction causes rolling" {
    var box = makeTestDynamicBody(100, 80, 40);
    box.velocity = Vec2.init(50, 100); // Moving right and down

    // Ramp is below and to the right
    var ramp = makeTestStaticBody(120, 100, 200, 20, 0.785); // 45 degrees

    // Normal points FROM box TO ramp (down-right at 45 degrees)
    const normal = Vec2.init(0.707, 0.707).normalize();

    // Contact at bottom-right corner of box
    const manifold = ContactManifold.init(
        Vec2.init(115, 95),
        normal,
        3.0,
    );

    std.debug.print("\n[TEST] box on ramp WITH FRICTION:\n", .{});
    std.debug.print("  box center: (100, 80)\n", .{});
    std.debug.print("  before: vel=({d:.1}, {d:.1}) ω={d:.3}\n", .{ box.velocity.x, box.velocity.y, box.angular_velocity });

    const r = manifold.point.sub(box.position);
    std.debug.print("  r (lever arm): ({d:.1}, {d:.1})\n", .{ r.x, r.y });
    std.debug.print("  r × normal = {d:.3} (if 0, normal impulse won't cause rotation)\n", .{r.cross2(normal)});

    // Use the FULL collision response with friction
    resolveWithMaterials(&box, &ramp, manifold, 0.0, 0.0, 0.5, 0.5, 3.0);

    std.debug.print("  after:  vel=({d:.1}, {d:.1}) ω={d:.3}\n", .{ box.velocity.x, box.velocity.y, box.angular_velocity });

    // With friction, the box should start spinning
    // Friction opposes the sliding velocity (tangent to surface)
    // This friction force applied at the contact point causes rotation
    std.debug.print("  (any non-zero ω means friction caused rotation)\n", .{});

    // Friction should cause SOME rotation (either direction depending on slide direction)
    // Box is sliding down-right, friction pulls it back (up-left along surface)
    // Friction at bottom-right corner pulling up-left = CCW = negative ω
    try std.testing.expect(box.angular_velocity != 0);
}

test "off-center contact causes rotation from normal impulse" {
    var box = makeTestDynamicBody(100, 100, 40);
    box.velocity = Vec2.init(0, 100); // Falling down

    var ground = makeTestStaticBody(100, 140, 200, 20, 0);

    // Contact at the RIGHT edge of box bottom (not center)
    // This creates a lever arm that's NOT parallel to normal
    const manifold = ContactManifold.init(
        Vec2.init(118, 120), // Right side of box bottom
        Vec2.init(0, 1), // Normal pointing DOWN
        5.0,
    );

    std.debug.print("\n[TEST] off-center ground hit:\n", .{});
    std.debug.print("  box center: (100, 100)\n", .{});
    std.debug.print("  contact: ({d:.1}, {d:.1})\n", .{ manifold.point.x, manifold.point.y });

    const r = manifold.point.sub(box.position);
    std.debug.print("  r (lever arm): ({d:.1}, {d:.1})\n", .{ r.x, r.y });
    std.debug.print("  normal: ({d:.1}, {d:.1})\n", .{ manifold.normal.x, manifold.normal.y });
    std.debug.print("  r × normal = {d:.3}\n", .{r.cross2(manifold.normal)});

    std.debug.print("  before: vel=({d:.1}, {d:.1}) ω={d:.3}\n", .{ box.velocity.x, box.velocity.y, box.angular_velocity });

    _ = resolveNormalImpulse(&box, &ground, getSolverData(&box, manifold.point), getSolverData(&ground, manifold.point), manifold, 0.5, 3.0);

    std.debug.print("  after:  vel=({d:.1}, {d:.1}) ω={d:.3}\n", .{ box.velocity.x, box.velocity.y, box.angular_velocity });

    // r = (18, 20), normal = (0, 1)
    // r × normal = 18 * 1 - 20 * 0 = 18 (non-zero!)
    // Impulse pushes box UP (opposite to normal)
    // Applied at right side = CCW rotation = negative ω
    try std.testing.expect(box.angular_velocity < 0);
}

test "realistic ramp scenario: box falling onto 20-degree ramp" {
    // Simulate ramps_example scenario: 25x25 box falling onto a tilted ramp
    var box = makeTestDynamicBody(200, 100, 25);
    box.velocity = Vec2.init(0, 100); // Falling straight down

    // Ramp tilted ~17 degrees (0.3 radians) - going down to the right
    // Ramp at position (200, 150)
    var ramp = makeTestStaticBody(200, 150, 250, 15, 0.3);

    // CRITICAL: Normal points FROM body1 (box) TO body2 (ramp)
    // Box is above ramp, so normal points DOWN (toward ramp)
    // The ramp is tilted, so the collision normal is the ramp's surface perpendicular
    // pointing FROM the box side (up) INTO the ramp = surface normal but flipped
    const ramp_angle: f32 = 0.3;
    // Surface normal points away from ramp surface = up-left
    // Collision normal points from box to ramp = DOWN into surface = opposite of surface normal
    const normal = Vec2.init(@sin(ramp_angle), @cos(ramp_angle)); // Points down-right (into ramp)

    // Contact point: where box corner hits ramp
    const contact = Vec2.init(212, 112);

    const manifold = ContactManifold.init(contact, normal, 3.0);

    std.debug.print("\n[TEST] Box falling onto tilted ramp (FIXED NORMAL):\n", .{});
    std.debug.print("  box center: (200, 100)\n", .{});
    std.debug.print("  ramp angle: {d:.2} rad ({d:.1} degrees)\n", .{ ramp_angle, ramp_angle * 180 / 3.14159 });
    std.debug.print("  contact: ({d:.1}, {d:.1})\n", .{ contact.x, contact.y });
    std.debug.print("  normal: ({d:.3}, {d:.3}) [points from box toward ramp]\n", .{ normal.x, normal.y });

    const r = contact.sub(box.position);
    std.debug.print("  r: ({d:.1}, {d:.1})\n", .{ r.x, r.y });
    std.debug.print("  r × normal = {d:.3}\n", .{r.cross2(normal)});

    // Check vrel to understand what impulse will do
    const vrel = Vec2.init(0, 0).sub(box.velocity); // v2 - v1, ramp is static
    const vn = vrel.dot(normal);
    std.debug.print("  vrel: ({d:.1}, {d:.1})\n", .{ vrel.x, vrel.y });
    std.debug.print("  vn = vrel.dot(normal) = {d:.3}\n", .{vn});
    std.debug.print("  (vn < 0 means approaching, > 0 means separating)\n", .{});

    std.debug.print("  before: vel=({d:.1}, {d:.1}) ω={d:.3}\n", .{ box.velocity.x, box.velocity.y, box.angular_velocity });

    // Full collision with friction
    resolveWithMaterials(&box, &ramp, manifold, 0.4, 0.4, 0.4, 0.4, 3.0);

    std.debug.print("  after:  vel=({d:.1}, {d:.1}) ω={d:.3}\n", .{ box.velocity.x, box.velocity.y, box.angular_velocity });

    // With correct normal (pointing down-right from box to ramp):
    // - Impulse pushes box OPPOSITE to normal = up-left
    // - Contact at bottom-right of box
    // - Up-left force at bottom-right = CCW rotation (negative ω)
    // - Velocity should change to slide along ramp (up-left component added)

    // Verify impulse was actually applied
    try std.testing.expect(box.velocity.y < 100); // Should have slowed/reversed
}
