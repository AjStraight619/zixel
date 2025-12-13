const std = @import("std");
const math = std.math;

const Vec2 = @import("../math/vec2.zig");
const Body = @import("body.zig").Body;
const ContactManifold = @import("narrowphase.zig").ContactManifold;

/// Thresholds used to avoid numerical noise in tangent handling.
const TANGENT_EPS: f32 = 1e-6;
const TANGENT_DEADZONE: f32 = 1e-4;

/// Impulse-based collision response.
/// Normal impulse resolves penetration and restitution.
/// Tangential impulse applies Coulomb friction.
/// Resolve collision using combined material properties.
///
/// Normal impulse is applied first.
/// Friction impulse is applied using the relative velocity *before* the normal impulse,
/// clamped by the magnitude of the normal impulse.
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
    // Combine material parameters using geometric mean.
    const restitution = @sqrt(restitution1 * restitution2);
    const friction = @sqrt(friction1 * friction2);

    const result = resolveNormalImpulse(
        body1,
        body2,
        m,
        restitution,
        restitution_clamp_threshold,
    );

    // Friction is only applied if a normal impulse was generated.
    applyFrictionImpulse(
        body1,
        body2,
        m,
        friction,
        result.jn,
        result.rel_before,
    );
}

/// Positional correction using a Baumgarte-style approach.
/// Executed during the position-iteration phase.
pub fn correctPositions(
    body1: *Body,
    body2: *Body,
    m: ContactManifold,
    correction_factor: f32,
) void {
    const b1_dyn = body1.kind == .dynamic;
    const b2_dyn = body2.kind == .dynamic;

    if (!b1_dyn and !b2_dyn) return;

    const inv_m1: f32 = if (b1_dyn) 1.0 / body1.mass else 0.0;
    const inv_m2: f32 = if (b2_dyn) 1.0 / body2.mass else 0.0;

    const inv_mass_sum = inv_m1 + inv_m2;
    if (inv_mass_sum <= 0.0) return;

    // Correction magnitude along the contact normal.
    const corr_mag = (m.penetration / inv_mass_sum) * correction_factor;
    const corr = m.normal.scale(corr_mag);

    if (b1_dyn) body1.position = body1.position.sub(corr.scale(inv_m1));
    if (b2_dyn) body2.position = body2.position.add(corr.scale(inv_m2));
}

/// Result of normal impulse resolution.
/// The relative velocity is returned so friction can be computed consistently.
const NormalImpulseResult = struct {
    jn: f32,
    rel_before: Vec2,
};

/// Compute and apply the normal impulse.
///
/// Returns the impulse magnitude and the relative velocity prior to impulse application.
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
    const inv_mass_sum = inv_m1 + inv_m2;

    if (inv_mass_sum <= 0.0) {
        return .{ .jn = 0.0, .rel_before = Vec2.zero };
    }

    // Relative velocity at the contact.
    const v1 = if (body1.kind != .static) body1.velocity else Vec2.zero;
    const v2 = if (body2.kind != .static) body2.velocity else Vec2.zero;
    const rel = v2.sub(v1);

    // Normal component of relative velocity.
    // vn > 0 indicates separating bodies.
    const vn = rel.dot(m.normal);

    if (vn > 0.0) {
        return .{ .jn = 0.0, .rel_before = rel };
    }

    // Suppress restitution at low speeds to reduce jitter.
    const e = if (@abs(vn) < restitution_clamp_threshold) 0.0 else restitution;

    // Normal impulse magnitude.
    var jn: f32 = -(1.0 + e) * vn;
    jn /= inv_mass_sum;

    const impulse = m.normal.scale(jn);

    if (b1_dyn) body1.velocity = body1.velocity.sub(impulse.scale(inv_m1));
    if (b2_dyn) body2.velocity = body2.velocity.add(impulse.scale(inv_m2));

    return .{ .jn = jn, .rel_before = rel };
}

/// Apply tangential friction impulse using Coulomb's law.
///
/// The tangential impulse is clamped by the magnitude of the normal impulse.
fn applyFrictionImpulse(
    body1: *Body,
    body2: *Body,
    m: ContactManifold,
    friction: f32,
    jn: f32,
    rel_before_normal: Vec2,
) void {
    if (jn == 0.0) return;

    const b1_dyn = body1.kind == .dynamic;
    const b2_dyn = body2.kind == .dynamic;

    const inv_m1: f32 = if (b1_dyn) 1.0 / body1.mass else 0.0;
    const inv_m2: f32 = if (b2_dyn) 1.0 / body2.mass else 0.0;

    const inv_mass_sum = inv_m1 + inv_m2;
    if (inv_mass_sum <= 0.0) return;

    // Tangential component of relative velocity.
    const vn = rel_before_normal.dot(m.normal);
    const tangent = rel_before_normal.sub(m.normal.scale(vn));

    if (tangent.length() < TANGENT_EPS) return;

    const t_hat = tangent.normalize();
    const vt = rel_before_normal.dot(t_hat);

    // Ignore extremely small tangent velocities to avoid micro jitter.
    if (@abs(vt) < TANGENT_DEADZONE) return;

    // Ideal tangential impulse magnitude.
    var jt: f32 = -vt / inv_mass_sum;

    // Coulomb friction clamp.
    const max_jt = friction * @abs(jn);
    jt = math.clamp(jt, -max_jt, max_jt);

    const impulse = t_hat.scale(jt);

    if (b1_dyn) body1.velocity = body1.velocity.sub(impulse.scale(inv_m1));
    if (b2_dyn) body2.velocity = body2.velocity.add(impulse.scale(inv_m2));
}
