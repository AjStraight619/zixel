const std = @import("std");
const Vec2 = @import("../math/vec2.zig");
const Body = @import("body.zig").Body;
const ContactManifold = @import("narrowphase.zig").ContactManifold;

/// Collision response and physics resolution
pub const CollisionResponse = struct {
    /// Resolve collision between two bodies using impulse-based method
    pub fn resolveCollision(body1: *Body, body2: *Body, manifold: ContactManifold, restitution: f32, restitution_clamp_threshold: f32) void {
        // Get masses (infinite mass for static and kinematic bodies)
        const body1_dynamic = body1.kind == .dynamic;
        const body2_dynamic = body2.kind == .dynamic;

        // Only resolve if at least one body can be affected (dynamic)
        if (!body1_dynamic and !body2_dynamic) return;

        // Get masses (infinite mass for static and kinematic bodies)
        const mass1 = if (body1_dynamic) body1.mass else std.math.inf(f32);
        const mass2 = if (body2_dynamic) body2.mass else std.math.inf(f32);
        const inv_mass1 = if (body1_dynamic) 1.0 / mass1 else 0.0;
        const inv_mass2 = if (body2_dynamic) 1.0 / mass2 else 0.0;

        // Get velocities (kinematic bodies have velocity, static don't)
        const vel1 = if (body1.kind != .static) body1.velocity else Vec2.zero;
        const vel2 = if (body2.kind != .static) body2.velocity else Vec2.zero;

        // Relative velocity
        const rel_vel = Vec2{
            .x = vel2.x - vel1.x,
            .y = vel2.y - vel1.y,
        };

        // Relative velocity in collision normal direction
        const vel_along_normal = rel_vel.x * manifold.normal.x + rel_vel.y * manifold.normal.y;

        // Don't resolve if velocities are separating
        if (vel_along_normal > 0.0) return;

        // Anti-jitter: If the closing velocity is very small, kill the bounce
        var e = restitution;
        if (vel_along_normal > -restitution_clamp_threshold) {
            e = 0.0;
        }

        // Calculate impulse scalar
        var j = -(1.0 + e) * vel_along_normal;
        j /= inv_mass1 + inv_mass2;

        // Apply impulse (only to dynamic bodies)
        const impulse = Vec2{
            .x = j * manifold.normal.x,
            .y = j * manifold.normal.y,
        };

        if (body1_dynamic) {
            body1.velocity.x -= impulse.x * inv_mass1;
            body1.velocity.y -= impulse.y * inv_mass1;
        }

        if (body2_dynamic) {
            body2.velocity.x += impulse.x * inv_mass2;
            body2.velocity.y += impulse.y * inv_mass2;
        }
    }

    /// Correct positions to resolve penetration
    pub fn correctPositions(body1: *Body, body2: *Body, manifold: ContactManifold, correction_factor: f32) void {
        const body1_dynamic = body1.kind == .dynamic;
        const body2_dynamic = body2.kind == .dynamic;

        // Only correct if at least one body can be moved (dynamic)
        if (!body1_dynamic and !body2_dynamic) return;

        const mass1 = if (body1_dynamic) body1.mass else std.math.inf(f32);
        const mass2 = if (body2_dynamic) body2.mass else std.math.inf(f32);
        const inv_mass1 = if (body1_dynamic) 1.0 / mass1 else 0.0;
        const inv_mass2 = if (body2_dynamic) 1.0 / mass2 else 0.0;

        const correction_magnitude = manifold.penetration / (inv_mass1 + inv_mass2) * correction_factor;
        const correction = Vec2{
            .x = correction_magnitude * manifold.normal.x,
            .y = correction_magnitude * manifold.normal.y,
        };

        // Only move dynamic bodies
        if (body1_dynamic) {
            body1.position.x -= correction.x * inv_mass1;
            body1.position.y -= correction.y * inv_mass1;
        }

        if (body2_dynamic) {
            body2.position.x += correction.x * inv_mass2;
            body2.position.y += correction.y * inv_mass2;
        }
    }

    /// Resolve collision with custom material properties
    pub fn resolveCollisionWithMaterials(body1: *Body, body2: *Body, manifold: ContactManifold, restitution1: f32, restitution2: f32, friction1: f32, friction2: f32, restitution_clamp_threshold: f32) void {
        // Combine material properties
        const combined_restitution = @sqrt(restitution1 * restitution2);
        const combined_friction = @sqrt(friction1 * friction2);

        // Resolve normal collision
        resolveCollision(body1, body2, manifold, combined_restitution, restitution_clamp_threshold);

        // Apply friction
        applyFriction(body1, body2, manifold, combined_friction);
    }

    /// Apply friction forces tangential to collision normal
    fn applyFriction(body1: *Body, body2: *Body, manifold: ContactManifold, friction: f32) void {
        const body1_dynamic = body1.kind == .dynamic;
        const body2_dynamic = body2.kind == .dynamic;

        // Only apply friction if at least one body can be affected (dynamic)
        if (!body1_dynamic and !body2_dynamic) return;

        // Get masses and inverse masses
        const mass1 = if (body1_dynamic) body1.mass else std.math.inf(f32);
        const mass2 = if (body2_dynamic) body2.mass else std.math.inf(f32);
        const inv_mass1 = if (body1_dynamic) 1.0 / mass1 else 0.0;
        const inv_mass2 = if (body2_dynamic) 1.0 / mass2 else 0.0;

        // Get velocities (kinematic bodies have velocity, static don't)
        const vel1 = if (body1.kind != .static) body1.velocity else Vec2.zero;
        const vel2 = if (body2.kind != .static) body2.velocity else Vec2.zero;

        // Relative velocity
        const rel_vel = Vec2{
            .x = vel2.x - vel1.x,
            .y = vel2.y - vel1.y,
        };

        // Calculate tangent vector (perpendicular to normal)
        const vel_dot_normal = rel_vel.x * manifold.normal.x + rel_vel.y * manifold.normal.y;
        const tangent = Vec2{
            .x = rel_vel.x - vel_dot_normal * manifold.normal.x,
            .y = rel_vel.y - vel_dot_normal * manifold.normal.y,
        };

        // Normalize tangent
        const tangent_length = @sqrt(tangent.x * tangent.x + tangent.y * tangent.y);
        if (tangent_length < 0.001) return; // No tangential velocity

        const tangent_norm = Vec2{
            .x = tangent.x / tangent_length,
            .y = tangent.y / tangent_length,
        };

        // Calculate friction impulse
        const vel_along_tangent = rel_vel.x * tangent_norm.x + rel_vel.y * tangent_norm.y;
        var friction_impulse = -vel_along_tangent / (inv_mass1 + inv_mass2);

        // Clamp friction impulse (Coulomb friction)
        const normal_impulse = manifold.penetration * (inv_mass1 + inv_mass2);
        const max_friction = friction * normal_impulse;
        friction_impulse = std.math.clamp(friction_impulse, -max_friction, max_friction);

        // Apply friction impulse (only to dynamic bodies)
        const friction_vector = Vec2{
            .x = friction_impulse * tangent_norm.x,
            .y = friction_impulse * tangent_norm.y,
        };

        if (body1_dynamic) {
            body1.velocity.x -= friction_vector.x * inv_mass1;
            body1.velocity.y -= friction_vector.y * inv_mass1;
        }

        if (body2_dynamic) {
            body2.velocity.x += friction_vector.x * inv_mass2;
            body2.velocity.y += friction_vector.y * inv_mass2;
        }
    }
};
