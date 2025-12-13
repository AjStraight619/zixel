// const std = @import("std");
// const math = std.math;
// const Vec2 = @import("../math/vec2.zig");
// const Body = @import("body.zig").Body;
// const ContactManifold = @import("narrowphase.zig").ContactManifold;
//
// /// Collision response and physics resolution
// pub const CollisionResponse = struct {
//     fn resolveCollision(
//         body1: *Body,
//         body2: *Body,
//         manifold: ContactManifold,
//         restitution: f32,
//         restitution_clamp_threshold: f32,
//     ) f32 {
//         const body1_dyn = body1.kind == .dynamic;
//         const body2_dyn = body2.kind == .dynamic;
//
//         const inv_m1: f32 = if (body1_dyn) 1.0 / body1.mass else 0.0;
//         const inv_m2: f32 = if (body2_dyn) 1.0 / body2.mass else 0.0;
//
//         const vel1 = if (body1.kind != .static) body1.velocity else Vec2.zero;
//         const vel2 = if (body2.kind != .static) body2.velocity else Vec2.zero;
//
//         const rel = Vec2{ .x = vel2.x - vel1.x, .y = vel2.y - vel1.y };
//         const vn = rel.x * manifold.normal.x + rel.y * manifold.normal.y;
//
//         // separating or resting (no impulse)
//         if (vn > 0.0) return 0.0;
//
//         // kill bounce at low speeds
//         const e = if (@abs(vn) < restitution_clamp_threshold) 0.0 else restitution;
//
//         var j = -(1.0 + e) * vn;
//         const inv_mass_sum = inv_m1 + inv_m2;
//         if (inv_mass_sum <= 0.0) return 0.0;
//
//         j /= inv_mass_sum;
//
//         const impulse = Vec2{ .x = j * manifold.normal.x, .y = j * manifold.normal.y };
//
//         if (body1_dyn) {
//             body1.velocity.x -= impulse.x * inv_m1;
//             body1.velocity.y -= impulse.y * inv_m1;
//         }
//         if (body2_dyn) {
//             body2.velocity.x += impulse.x * inv_m2;
//             body2.velocity.y += impulse.y * inv_m2;
//         }
//
//         return j;
//     }
//
//     /// Correct positions to resolve penetration
//     pub fn correctPositions(body1: *Body, body2: *Body, manifold: ContactManifold, correction_factor: f32) void {
//         const body1_dynamic = body1.kind == .dynamic;
//         const body2_dynamic = body2.kind == .dynamic;
//
//         // Only correct if at least one body can be moved (dynamic)
//         if (!body1_dynamic and !body2_dynamic) return;
//
//         const mass1 = if (body1_dynamic) body1.mass else std.math.inf(f32);
//         const mass2 = if (body2_dynamic) body2.mass else std.math.inf(f32);
//         const inv_mass1 = if (body1_dynamic) 1.0 / mass1 else 0.0;
//         const inv_mass2 = if (body2_dynamic) 1.0 / mass2 else 0.0;
//
//         const correction_magnitude = manifold.penetration / (inv_mass1 + inv_mass2) * correction_factor;
//         const correction = Vec2{
//             .x = correction_magnitude * manifold.normal.x,
//             .y = correction_magnitude * manifold.normal.y,
//         };
//
//         // Only move dynamic bodies
//         if (body1_dynamic) {
//             body1.position.x -= correction.x * inv_mass1;
//             body1.position.y -= correction.y * inv_mass1;
//         }
//
//         if (body2_dynamic) {
//             body2.position.x += correction.x * inv_mass2;
//             body2.position.y += correction.y * inv_mass2;
//         }
//     }
//
//     /// Resolve collision with custom material properties
//     pub fn resolveCollisionWithMaterials(body1: *Body, body2: *Body, manifold: ContactManifold, restitution1: f32, restitution2: f32, friction1: f32, friction2: f32, restitution_clamp_threshold: f32) void {
//         // Combine material properties
//         const e = @sqrt(restitution1 * restitution2);
//         const mu = @sqrt(friction1 * friction2);
//
//         // Resolve normal collision and get impulse
//         const j = resolveCollision(body1, body2, manifold, e, restitution_clamp_threshold);
//
//         // Apply friction
//         applyFriction(body1, body2, manifold, mu, j);
//     }
//
//     fn applyFriction(body1: *Body, body2: *Body, manifold: ContactManifold, mu: f32, j: f32) void {
//         if (j == 0.0) return;
//
//         const b1_dyn = body1.kind == .dynamic;
//         const b2_dyn = body2.kind == .dynamic;
//
//         const inv_m1: f32 = if (b1_dyn) 1.0 / body1.mass else 0.0;
//         const inv_m2: f32 = if (b2_dyn) 1.0 / body2.mass else 0.0;
//         const inv_mass_sum = inv_m1 + inv_m2;
//         if (inv_mass_sum <= 0.0) return;
//
//         const v1 = if (body1.kind != .static) body1.velocity else Vec2.zero;
//         const v2 = if (body2.kind != .static) body2.velocity else Vec2.zero;
//
//         const rel = Vec2{ .x = v2.x - v1.x, .y = v2.y - v1.y };
//
//         // tangent = rel - (rel·n)*n
//         const vn = rel.x * manifold.normal.x + rel.y * manifold.normal.y;
//         const tx = rel.x - vn * manifold.normal.x;
//         const ty = rel.y - vn * manifold.normal.y;
//
//         const t_len = @sqrt(tx * tx + ty * ty);
//         if (t_len < 1e-6) return;
//
//         const tnx = tx / t_len;
//         const tny = ty / t_len;
//
//         const vt = rel.x * tnx + rel.y * tny;
//
//         var jt = -vt / inv_mass_sum;
//
//         // Coulomb clamp using *real* normal impulse magnitude
//         const max_jt = mu * @abs(j);
//         jt = std.math.clamp(jt, -max_jt, max_jt);
//
//         const friction_imp = Vec2{ .x = jt * tnx, .y = jt * tny };
//
//         if (b1_dyn) {
//             body1.velocity.x -= friction_imp.x * inv_m1;
//             body1.velocity.y -= friction_imp.y * inv_m1;
//         }
//         if (b2_dyn) {
//             body2.velocity.x += friction_imp.x * inv_m2;
//             body2.velocity.y += friction_imp.y * inv_m2;
//         }
//     }
// };

const std = @import("std");
const math = std.math;

const Vec2 = @import("../math/vec2.zig");
const Body = @import("body.zig").Body;
const ContactManifold = @import("narrowphase.zig").ContactManifold;

pub const CollisionResponse = @This();

/// Small epsilon for "no tangent" checks.
const TANGENT_EPS: f32 = 1e-6;

/// Resolve collision using combined material properties:
/// - normal impulse (restitution)
/// - friction impulse (Coulomb clamp, uses |j| from normal impulse)
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
    // Combine material properties (common/simple choice)
    const e: f32 = @sqrt(restitution1 * restitution2);

    // "mu" is the conventional symbol for coefficient of friction.
    // You can rename this to friction_coeff if you prefer.
    const mu: f32 = @sqrt(friction1 * friction2);

    // Normal impulse (returns j, and the relative velocity used for friction)
    const res = resolveNormalImpulse(body1, body2, m, e, restitution_clamp_threshold);

    // Friction impulse (only if we applied a normal impulse)
    applyFrictionImpulse(body1, body2, m, mu, res.j, res.rel_vel);
}

/// Positional correction (Baumgarte-style), called during your position iterations.
pub fn correctPositions(
    body1: *Body,
    body2: *Body,
    m: ContactManifold,
    correction_factor: f32,
) void {
    const b1_dyn = body1.kind == .dynamic;
    const b2_dyn = body2.kind == .dynamic;

    // Only move dynamics
    if (!b1_dyn and !b2_dyn) return;

    const inv_m1: f32 = if (b1_dyn) 1.0 / body1.mass else 0.0;
    const inv_m2: f32 = if (b2_dyn) 1.0 / body2.mass else 0.0;

    const inv_mass_sum = inv_m1 + inv_m2;
    if (inv_mass_sum <= 0.0) return;

    // magnitude along normal
    const corr_mag = (m.penetration / inv_mass_sum) * correction_factor;

    const corr = Vec2{
        .x = corr_mag * m.normal.x,
        .y = corr_mag * m.normal.y,
    };

    if (b1_dyn) {
        body1.position.x -= corr.x * inv_m1;
        body1.position.y -= corr.y * inv_m1;
    }
    if (b2_dyn) {
        body2.position.x += corr.x * inv_m2;
        body2.position.y += corr.y * inv_m2;
    }
}

/// Internal result so friction can use the *same* relative velocity used for the normal impulse.
const NormalImpulseResult = struct {
    j: f32,
    rel_vel: Vec2,
};

/// Compute and apply the normal impulse.
/// Returns the normal impulse magnitude j (0 if none), and the relative velocity used.
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
        return .{ .j = 0.0, .rel_vel = Vec2.zero };
    }

    const v1 = if (body1.kind != .static) body1.velocity else Vec2.zero;
    const v2 = if (body2.kind != .static) body2.velocity else Vec2.zero;

    const rel = Vec2{ .x = v2.x - v1.x, .y = v2.y - v1.y };

    const vn = rel.x * m.normal.x + rel.y * m.normal.y;

    // Separating -> no impulse
    if (vn > 0.0) {
        return .{ .j = 0.0, .rel_vel = rel };
    }

    // Kill bounce at low speeds to reduce jitter
    const e: f32 = if (@abs(vn) < restitution_clamp_threshold) 0.0 else restitution;

    var j: f32 = -(1.0 + e) * vn;
    j /= inv_mass_sum;

    const imp = Vec2{ .x = j * m.normal.x, .y = j * m.normal.y };

    if (b1_dyn) {
        body1.velocity.x -= imp.x * inv_m1;
        body1.velocity.y -= imp.y * inv_m1;
    }
    if (b2_dyn) {
        body2.velocity.x += imp.x * inv_m2;
        body2.velocity.y += imp.y * inv_m2;
    }

    return .{ .j = j, .rel_vel = rel };
}

/// Apply tangential friction impulse using Coulomb clamp: |jt| <= mu * |j|
fn applyFrictionImpulse(
    body1: *Body,
    body2: *Body,
    m: ContactManifold,
    mu: f32,
    j: f32,
    rel_before_normal: Vec2,
) void {
    if (j == 0.0) return;

    const b1_dyn = body1.kind == .dynamic;
    const b2_dyn = body2.kind == .dynamic;

    const inv_m1: f32 = if (b1_dyn) 1.0 / body1.mass else 0.0;
    const inv_m2: f32 = if (b2_dyn) 1.0 / body2.mass else 0.0;

    const inv_mass_sum = inv_m1 + inv_m2;
    if (inv_mass_sum <= 0.0) return;

    // Tangent = rel - (rel·n) n
    const vn = rel_before_normal.x * m.normal.x + rel_before_normal.y * m.normal.y;
    const tx = rel_before_normal.x - vn * m.normal.x;
    const ty = rel_before_normal.y - vn * m.normal.y;

    const t_len = @sqrt(tx * tx + ty * ty);
    if (t_len < TANGENT_EPS) return;

    const tnx = tx / t_len;
    const tny = ty / t_len;

    const vt = rel_before_normal.x * tnx + rel_before_normal.y * tny;

    // Optional: tiny deadzone so we don't “micro-correct” tangent jitter
    if (@abs(vt) < 1e-4) return;

    var jt: f32 = -vt / inv_mass_sum;

    // Coulomb clamp: max friction impulse proportional to normal impulse magnitude
    const max_jt = mu * @abs(j);
    jt = math.clamp(jt, -max_jt, max_jt);

    const fr = Vec2{ .x = jt * tnx, .y = jt * tny };

    if (b1_dyn) {
        body1.velocity.x -= fr.x * inv_m1;
        body1.velocity.y -= fr.y * inv_m1;
    }
    if (b2_dyn) {
        body2.velocity.x += fr.x * inv_m2;
        body2.velocity.y += fr.y * inv_m2;
    }
}
