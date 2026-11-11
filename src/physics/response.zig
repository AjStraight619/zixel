const std = @import("std");
const test_log = std.log.scoped(.zixel_physics_test);
const math = std.math;

const Vec2 = @import("../math/Vec2.zig");
const Body = @import("Body.zig");
const ContactManifold = @import("narrowphase.zig").ContactManifold;

// Small thresholds to avoid doing tiny useless corrections (micro-jitter).
const tangent_eps: f32 = 1e-6;
const tangent_deadzone: f32 = 1e-4;

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

    /// The same contact, with the body treated as infinitely heavy.
    fn immovable(self: SolverData) SolverData {
        return .{ .inv_mass = 0.0, .inv_inertia = 0.0, .r = self.r };
    }
};

/// When a load resting on a sleeping body should leave it asleep.
pub const SleepPolicy = struct {
    /// Unit gravity direction, or null when there is no gravity. With null,
    /// every non-zero impulse wakes a sleeping body.
    down: ?Vec2 = null,
    /// A dynamic body pressing down on a sleeper more slowly than this (world
    /// units/s) is resting on it rather than hitting it.
    wake_speed: f32 = 0.0,
};

/// Velocity of the body's material at the contact point.
fn contactVelocity(body: *const Body, sd: SolverData) Vec2 {
    if (body.kind == .static) return Vec2.zero;
    return body.velocity.add(Vec2{ .x = -body.angular_velocity * sd.r.y, .y = body.angular_velocity * sd.r.x });
}

/// Helper to build the cache.
fn getSolverData(body: *Body, contact_point: Vec2) SolverData {
    return .{
        .inv_mass = body.invMass(),
        .inv_inertia = body.invInertia(),
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
    sleep_policy: SleepPolicy,
) void {
    // 1. Pre-calculate solver data (Mass, Inertia, R-vector)
    var sd1 = getSolverData(body1, m.point);
    var sd2 = getSolverData(body2, m.point);

    // A dynamic body settling slowly onto a sleeping one rests on it as it would
    // on static ground. Without this, the weight of an awake body wakes whatever
    // is underneath it every step and stacks can never fall asleep. Impacts,
    // sideways pushes and kinematic bodies still wake sleepers as usual.
    if (sleep_policy.down) |down| {
        const rel_speed = contactVelocity(body2, sd2).sub(contactVelocity(body1, sd1)).length();
        if (rel_speed < sleep_policy.wake_speed) {
            const facing_down = m.normal.dot(down); // > 0: body2 is below body1
            if (body2.isSleeping() and body1.kind == .dynamic and facing_down > 0) sd2 = sd2.immovable();
            if (body1.isSleeping() and body2.kind == .dynamic and facing_down < 0) sd1 = sd1.immovable();
        }
    }

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
    const v1 = contactVelocity(body1, sd1);
    const v2 = contactVelocity(body2, sd2);

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
    // No fixed cap here: the impulse needed to stop a body scales with its mass,
    // so a constant limit lets heavy bodies sink through whatever supports them.
    const jn = -(1.0 + e) * vn / k;

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

    if (tangent.length() < tangent_eps) return;
    const t_hat = tangent.normalize();

    // 2. Check tangential velocity magnitude
    const vt = vrel_old.dot(t_hat);
    if (@abs(vt) < tangent_deadzone) return;

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
    // Nothing to change for static, kinematic, or deliberately undisturbed bodies.
    if (body.kind != .dynamic or (sd.inv_mass == 0.0 and sd.inv_inertia == 0.0)) return;

    // Wake impacted bodies, but preserve the sleep timer of already-awake
    // bodies so resting support impulses do not prevent them from settling.
    if (body.isSleeping() and (impulse.x != 0 or impulse.y != 0)) body.wakeUp();

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
    // Sleeping bodies are at rest on their support and act as immovable here.
    // Moving them would shift a body that is not being simulated; an impulse
    // from a real impact (or losing its support) is what wakes a sleeper.
    const inv_m1 = if (body1.isSleeping()) 0.0 else body1.invMass();
    const inv_m2 = if (body2.isSleeping()) 0.0 else body2.invMass();
    const sum = inv_m1 + inv_m2;

    if (sum <= 0.0) return;

    const corr_mag = (m.penetration / sum) * correction_factor;
    const corr = m.normal.scale(corr_mag);

    if (inv_m1 > 0) body1.position = body1.position.sub(corr.scale(inv_m1));
    if (inv_m2 > 0) body2.position = body2.position.add(corr.scale(inv_m2));
}

const PhysicsShape = @import("../math/shapes.zig").PhysicsShape;

test "kinematic contact velocity transfers motion in either body order" {
    const Case = struct { kind: Body.BodyKind, velocity: f32, expected: f32 };
    for ([_]Case{
        .{ .kind = .kinematic, .velocity = -10, .expected = -10 },
        .{ .kind = .kinematic, .velocity = 10, .expected = 0 },
        .{ .kind = .static, .velocity = -10, .expected = 0 },
    }) |case| {
        for ([_]bool{ false, true }) |reverse| {
            var dynamic = Body.initDynamic(PhysicsShape.circ(1), Vec2.zero, .{});
            var other = Body.initKinematic(PhysicsShape.circ(1), Vec2.init(2, 0), .{});
            other.kind = case.kind;
            other.velocity.x = case.velocity;
            const normal = Vec2.init(if (reverse) -1 else 1, 0);
            const manifold = ContactManifold.init(Vec2.init(1, 0), normal, 0);
            const a = if (reverse) &other else &dynamic;
            const b = if (reverse) &dynamic else &other;
            resolveWithMaterials(a, b, manifold, 0, 0, 0, 0, 0, .{});
            try std.testing.expectApproxEqAbs(case.expected, dynamic.velocity.x, 0.0001);
            try std.testing.expectEqual(case.velocity, other.velocity.x);
            try std.testing.expectEqual(@as(f32, 0), other.angular_velocity);
        }
    }
}

test "rotating kinematic bodies contribute angular contact velocity" {
    for ([_]bool{ false, true }) |reverse| {
        var dynamic = Body.initDynamic(PhysicsShape.circ(1), Vec2.init(-1, 1), .{});
        var kinematic = Body.initKinematic(PhysicsShape.rect(2, 2), Vec2.zero, .{});
        kinematic.angular_velocity = 10;
        // At (0,1), the rotating surface moves left at 10 units per second.
        const manifold = ContactManifold.init(Vec2.init(0, 1), Vec2.init(if (reverse) -1 else 1, 0), 0);
        resolveWithMaterials(if (reverse) &kinematic else &dynamic, if (reverse) &dynamic else &kinematic, manifold, 0, 0, 0, 0, 0, .{});
        try std.testing.expectApproxEqAbs(@as(f32, -10), dynamic.velocity.x, 0.0001);
        try std.testing.expectEqual(@as(f32, 10), kinematic.angular_velocity);
        try std.testing.expectEqual(Vec2.zero, kinematic.velocity);
    }
}

test "moving kinematic surfaces contribute tangential velocity to friction" {
    var dynamic = Body.initDynamic(PhysicsShape.circ(1), Vec2.zero, .{});
    var kinematic = Body.initKinematic(PhysicsShape.rect(2, 2), Vec2.init(0, 2), .{ .velocity = .{ .x = 4, .y = -10 } });
    const manifold = ContactManifold.init(Vec2.init(0, 1), Vec2.init(0, 1), 0);
    resolveWithMaterials(&dynamic, &kinematic, manifold, 0, 0, 1, 1, 0, .{});
    try std.testing.expectApproxEqAbs(@as(f32, 4.0 / 3.0), dynamic.velocity.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, -10), dynamic.velocity.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, -8.0 / 3.0), dynamic.angular_velocity, 0.0001);
    try std.testing.expectEqual(Vec2.init(4, -10), kinematic.velocity);
    try std.testing.expectEqual(@as(f32, 0), kinematic.angular_velocity);
}

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

    test_log.debug("[TEST] box falling on flat ground:", .{});
    test_log.debug("  before: vel=({d:.1}, {d:.1}) ω={d:.3}", .{ box.velocity.x, box.velocity.y, box.angular_velocity });

    // vrel = v2 - v1 = 0 - (0, 100) = (0, -100)
    // vn = vrel.dot(normal) = (0, -100).dot(0, 1) = -100 (approaching)
    // jn = -(1+e) * vn / k = -(1.5) * (-100) / k = 150 / k
    // impulse = normal * jn = (0, jn) pushing ground down, box up

    _ = resolveNormalImpulse(&box, &ground, getSolverData(&box, manifold.point), getSolverData(&ground, manifold.point), manifold, 0.5, 3.0);

    test_log.debug("  after:  vel=({d:.1}, {d:.1}) ω={d:.3}", .{ box.velocity.x, box.velocity.y, box.angular_velocity });

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

    test_log.debug("[TEST] box on ramp WITH FRICTION:", .{});
    test_log.debug("  box center: (100, 80)", .{});
    test_log.debug("  before: vel=({d:.1}, {d:.1}) ω={d:.3}", .{ box.velocity.x, box.velocity.y, box.angular_velocity });

    const r = manifold.point.sub(box.position);
    test_log.debug("  r (lever arm): ({d:.1}, {d:.1})", .{ r.x, r.y });
    test_log.debug("  r × normal = {d:.3} (if 0, normal impulse won't cause rotation)", .{r.cross2(normal)});

    // Use the FULL collision response with friction
    resolveWithMaterials(&box, &ramp, manifold, 0.0, 0.0, 0.5, 0.5, 3.0, .{});

    test_log.debug("  after:  vel=({d:.1}, {d:.1}) ω={d:.3}", .{ box.velocity.x, box.velocity.y, box.angular_velocity });

    // With friction, the box should start spinning
    // Friction opposes the sliding velocity (tangent to surface)
    // This friction force applied at the contact point causes rotation
    test_log.debug("  (any non-zero ω means friction caused rotation)", .{});

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

    test_log.debug("[TEST] off-center ground hit:", .{});
    test_log.debug("  box center: (100, 100)", .{});
    test_log.debug("  contact: ({d:.1}, {d:.1})", .{ manifold.point.x, manifold.point.y });

    const r = manifold.point.sub(box.position);
    test_log.debug("  r (lever arm): ({d:.1}, {d:.1})", .{ r.x, r.y });
    test_log.debug("  normal: ({d:.1}, {d:.1})", .{ manifold.normal.x, manifold.normal.y });
    test_log.debug("  r × normal = {d:.3}", .{r.cross2(manifold.normal)});

    test_log.debug("  before: vel=({d:.1}, {d:.1}) ω={d:.3}", .{ box.velocity.x, box.velocity.y, box.angular_velocity });

    _ = resolveNormalImpulse(&box, &ground, getSolverData(&box, manifold.point), getSolverData(&ground, manifold.point), manifold, 0.5, 3.0);

    test_log.debug("  after:  vel=({d:.1}, {d:.1}) ω={d:.3}", .{ box.velocity.x, box.velocity.y, box.angular_velocity });

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

    test_log.debug("[TEST] Box falling onto tilted ramp (FIXED NORMAL):", .{});
    test_log.debug("  box center: (200, 100)", .{});
    test_log.debug("  ramp angle: {d:.2} rad ({d:.1} degrees)", .{ ramp_angle, ramp_angle * 180 / 3.14159 });
    test_log.debug("  contact: ({d:.1}, {d:.1})", .{ contact.x, contact.y });
    test_log.debug("  normal: ({d:.3}, {d:.3}) [points from box toward ramp]", .{ normal.x, normal.y });

    const r = contact.sub(box.position);
    test_log.debug("  r: ({d:.1}, {d:.1})", .{ r.x, r.y });
    test_log.debug("  r × normal = {d:.3}", .{r.cross2(normal)});

    // Check vrel to understand what impulse will do
    const vrel = Vec2.init(0, 0).sub(box.velocity); // v2 - v1, ramp is static
    const vn = vrel.dot(normal);
    test_log.debug("  vrel: ({d:.1}, {d:.1})", .{ vrel.x, vrel.y });
    test_log.debug("  vn = vrel.dot(normal) = {d:.3}", .{vn});
    test_log.debug("  (vn < 0 means approaching, > 0 means separating)", .{});

    test_log.debug("  before: vel=({d:.1}, {d:.1}) ω={d:.3}", .{ box.velocity.x, box.velocity.y, box.angular_velocity });

    // Full collision with friction
    resolveWithMaterials(&box, &ramp, manifold, 0.4, 0.4, 0.4, 0.4, 3.0, .{});

    test_log.debug("  after:  vel=({d:.1}, {d:.1}) ω={d:.3}", .{ box.velocity.x, box.velocity.y, box.angular_velocity });

    // With correct normal (pointing down-right from box to ramp):
    // - Impulse pushes box OPPOSITE to normal = up-left
    // - Contact at bottom-right of box
    // - Up-left force at bottom-right = CCW rotation (negative ω)
    // - Velocity should change to slide along ramp (up-left component added)

    // Verify impulse was actually applied
    try std.testing.expect(box.velocity.y < 100); // Should have slowed/reversed
}

test "a slow load from above leaves a sleeper asleep; impacts and side pushes wake it" {
    const policy = SleepPolicy{ .down = Vec2.init(0, 1), .wake_speed = 25 };
    const Case = struct { velocity: Vec2, normal: Vec2, wakes: bool };
    for ([_]Case{
        // Resting on top (normal points from the load down to the sleeper).
        .{ .velocity = Vec2.init(0, 10), .normal = Vec2.init(0, 1), .wakes = false },
        // Dropped onto it.
        .{ .velocity = Vec2.init(0, 100), .normal = Vec2.init(0, 1), .wakes = true },
        // Nudged from the side, however slowly.
        .{ .velocity = Vec2.init(10, 0), .normal = Vec2.init(1, 0), .wakes = true },
    }) |case| {
        for ([_]bool{ false, true }) |reverse| {
            var load = Body.initDynamic(PhysicsShape.circ(1), Vec2.zero, .{ .velocity = case.velocity });
            var sleeper = Body.initDynamic(PhysicsShape.circ(1), case.normal.scale(2), .{});
            sleeper.putToSleep();
            const manifold = ContactManifold.init(case.normal, if (reverse) case.normal.negate() else case.normal, 0);
            resolveWithMaterials(if (reverse) &sleeper else &load, if (reverse) &load else &sleeper, manifold, 0, 0, 0, 0, 3, policy);
            try std.testing.expectEqual(case.wakes, !sleeper.isSleeping());
            if (!case.wakes) {
                // The load stops dead, as it would on static ground.
                try std.testing.expectEqual(Vec2.zero, sleeper.velocity);
                try std.testing.expectApproxEqAbs(@as(f32, 0), load.velocity.y, 0.0001);
            }
        }
    }
}
