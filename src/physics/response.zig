const std = @import("std");
const math = std.math;

const Vec2 = @import("../math/vec2.zig");
const Body = @import("body.zig").Body;
const ContactManifold = @import("narrowphase.zig").ContactManifold;

// Small thresholds to avoid doing tiny useless corrections.
const TANGENT_EPS: f32 = 1e-6;
const TANGENT_DEADZONE: f32 = 1e-4;

/// Entry point for collision response.
/// Handles bounce first, then friction.
/// This is called once per collision per physics step.
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
    // Combine material properties in a simple, symmetric way.
    const restitution: f32 = @sqrt(restitution1 * restitution2);
    const friction: f32 = @sqrt(friction1 * friction2);

    // Resolve bounce along the contact normal.
    // This also returns the relative velocity at the contact point
    // before the impulse, which friction needs.
    const res = resolveNormalImpulse(body1, body2, m, restitution, restitution_clamp_threshold);

    // Apply friction along the tangent direction.
    applyFrictionImpulse(body1, body2, m, friction, res.jn, res.vrel_before);
}

/// Push overlapping bodies apart after collision detection.
/// This runs multiple times per step to stabilize stacks.
pub fn correctPositions(
    body1: *Body,
    body2: *Body,
    m: ContactManifold,
    correction_factor: f32,
) void {
    const b1_dyn = body1.kind == .dynamic;
    const b2_dyn = body2.kind == .dynamic;

    // If neither body can move, there is nothing to correct.
    if (!b1_dyn and !b2_dyn) return;

    const inv_m1: f32 = if (b1_dyn) 1.0 / body1.mass else 0.0;
    const inv_m2: f32 = if (b2_dyn) 1.0 / body2.mass else 0.0;

    const inv_mass_sum = inv_m1 + inv_m2;
    if (inv_mass_sum <= 0.0) return;

    // Move bodies apart along the collision normal,
    // scaled by how movable they are.
    const corr_mag = (m.penetration / inv_mass_sum) * correction_factor;
    const corr = m.normal.scale(corr_mag);

    if (b1_dyn) body1.position = body1.position.sub(corr.scale(inv_m1));
    if (b2_dyn) body2.position = body2.position.add(corr.scale(inv_m2));
}

/// Result from the normal impulse step.
/// Used so friction can see the same contact velocity.
const NormalImpulseResult = struct {
    jn: f32,
    vrel_before: Vec2,
};

/// Handles bounce along the collision normal.
/// Updates linear and angular velocity.
fn resolveNormalImpulse(
    body1: *Body,
    body2: *Body,
    m: ContactManifold,
    restitution: f32,
    restitution_clamp_threshold: f32,
) NormalImpulseResult {
    const b1_dyn = body1.kind == .dynamic;
    const b2_dyn = body2.kind == .dynamic;

    const inv_m1: f32 = if (b1_dyn) 1.0 / body1.mass else 0.0;
    const inv_m2: f32 = if (b2_dyn) 1.0 / body2.mass else 0.0;
    const inv_i1: f32 = if (b1_dyn) 1.0 / body1.inertia else 0.0;
    const inv_i2: f32 = if (b2_dyn) 1.0 / body2.inertia else 0.0;

    // No impulse if nothing can move.
    if (inv_m1 + inv_m2 <= 0.0) {
        return .{ .jn = 0.0, .vrel_before = Vec2.zero };
    }

    // Offset from each center to the contact point.
    const r1 = m.point.sub(body1.position);
    const r2 = m.point.sub(body2.position);

    // Velocity at the contact point includes both linear motion
    // and rotation around the center.
    const v1 = if (body1.kind != .static) body1.velocity else Vec2.zero;
    const v2 = if (body2.kind != .static) body2.velocity else Vec2.zero;

    const w1: f32 = if (b1_dyn) body1.angular_velocity else 0.0;
    const w2: f32 = if (b2_dyn) body2.angular_velocity else 0.0;

    const v1c = v1.add(Vec2{ .x = -w1 * r1.y, .y = w1 * r1.x });
    const v2c = v2.add(Vec2{ .x = -w2 * r2.y, .y = w2 * r2.x });

    const vrel = v2c.sub(v1c);

    // How fast the contact points are moving toward each other.
    const vn = vrel.dot(m.normal);

    // If already separating, skip.
    if (vn > 0.0) {
        return .{ .jn = 0.0, .vrel_before = vrel };
    }

    // Turn off bounce when impact speed is very small.
    const e: f32 = if (@abs(vn) < restitution_clamp_threshold) 0.0 else restitution;

    // How hard it is to push along the normal,
    // including rotation effects.
    const rn1 = r1.cross2(m.normal);
    const rn2 = r2.cross2(m.normal);

    const k = (inv_m1 + inv_m2) + (rn1 * rn1) * inv_i1 + (rn2 * rn2) * inv_i2;

    if (k <= 0.0) {
        return .{ .jn = 0.0, .vrel_before = vrel };
    }

    var jn: f32 = -(1.0 + e) * vn;
    jn /= k;

    applyImpulse(body1, body2, m.point, m.normal.scale(jn));

    return .{ .jn = jn, .vrel_before = vrel };
}

/// Applies friction along the surface at the contact point.
/// Uses the relative velocity from before the normal impulse.
fn applyFrictionImpulse(
    body1: *Body,
    body2: *Body,
    m: ContactManifold,
    friction: f32,
    jn: f32,
    vrel_before_normal: Vec2,
) void {
    if (jn == 0.0) return;

    const b1_dyn = body1.kind == .dynamic;
    const b2_dyn = body2.kind == .dynamic;

    const inv_m1: f32 = if (b1_dyn) 1.0 / body1.mass else 0.0;
    const inv_m2: f32 = if (b2_dyn) 1.0 / body2.mass else 0.0;
    const inv_i1: f32 = if (b1_dyn) 1.0 / body1.inertia else 0.0;
    const inv_i2: f32 = if (b2_dyn) 1.0 / body2.inertia else 0.0;

    // Remove the normal part, leaving only sideways motion.
    const vn = vrel_before_normal.dot(m.normal);
    const tangent = vrel_before_normal.sub(m.normal.scale(vn));

    if (tangent.length() < TANGENT_EPS) return;

    const t_hat = tangent.normalize();
    const vt = vrel_before_normal.dot(t_hat);

    // Ignore extremely small sideways motion.
    if (@abs(vt) < TANGENT_DEADZONE) return;

    const r1 = m.point.sub(body1.position);
    const r2 = m.point.sub(body2.position);

    // How hard it is to push sideways at the contact point.
    const rt1 = r1.cross2(t_hat);
    const rt2 = r2.cross2(t_hat);

    const k = (inv_m1 + inv_m2) + (rt1 * rt1) * inv_i1 + (rt2 * rt2) * inv_i2;

    if (k <= 0.0) return;

    var jt: f32 = -vt / k;

    // Limit friction based on the normal impulse.
    const max_jt = friction * @abs(jn);
    jt = math.clamp(jt, -max_jt, max_jt);

    applyImpulse(body1, body2, m.point, t_hat.scale(jt));
}

/// Applies an impulse at a world-space point.
/// Updates both linear and angular velocity.
fn applyImpulse(body1: *Body, body2: *Body, point: Vec2, impulse: Vec2) void {
    const b1_dyn = body1.kind == .dynamic;
    const b2_dyn = body2.kind == .dynamic;

    if (!b1_dyn and !b2_dyn) return;

    if (b1_dyn) {
        const inv_m1 = 1.0 / body1.mass;
        body1.velocity = body1.velocity.sub(impulse.scale(inv_m1));

        // Off-center impulse causes rotation.
        const r1 = point.sub(body1.position);
        const inv_i1 = 1.0 / body1.inertia;
        body1.angular_velocity -= r1.cross2(impulse) * inv_i1;
    }

    if (b2_dyn) {
        const inv_m2 = 1.0 / body2.mass;
        body2.velocity = body2.velocity.add(impulse.scale(inv_m2));

        const r2 = point.sub(body2.position);
        const inv_i2 = 1.0 / body2.inertia;
        body2.angular_velocity += r2.cross2(impulse) * inv_i2;
    }
}
