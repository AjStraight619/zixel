# Physics benchmark experiment

Measured on 2026-09-16 against runtime commit `3138de2` using Zig 0.16.0.
The benchmark changes are retained; the runtime experiments are temporary.

## Findings

- Compiler optimization has a large effect: the crowded 2,000-body case averages
  about 43 ms per physics step in Debug and 5.9 ms in ReleaseFast.
- Correcting negative-coordinate rectangle bounds removes thousands of false
  candidates in the isolated broadphase test.
- Caching each body's bounds during broadphase reduces the crowded case's mean
  time by about 29% compared with the bounds-corrected version. It increases the
  sparse case's mean by about 19%, and increases memory used by cell entries.
- The enclosure fails to contain many bodies. These timings describe the current
  implementation, including its incorrect behavior; they do not establish stable
  pile performance or full-engine FPS.

## Method

Hardware: Intel Core i5-13420H, Linux x86_64. Each measured executable was pinned
with `taskset -c 0`. The CPU governor was `powersave`; clocks were not locked and
other system activity was not controlled. Compilation completed before timing.

Each scenario recreates its world five times from seed 42. Each run warms up for
60 updates, then measures 180 updates using `std.Io.Clock.awake`. There are 900
measured updates per scenario per suite. Full-physics scenarios pass exactly
`physics_time_step` and check the actual step count. Broadphase-only scenarios
rebuild candidates without simulating motion.

Setup, state validation, sorting and reporting are excluded from timing. Allocation
inside updates remains included, using the physics sample's `page_allocator`
wrapped by `CountingAllocator`. Reported allocation growth excludes warm-up and
setup; it is cumulative allocated/grown bytes, not peak live memory or allocation
call count. The editor uses a different allocator.

All scenarios check finite positions and velocities, and identical final-state
hashes across their five repeats. Hashes cover positions, velocities, rotations,
angular velocities and sleeping flags. Counts of candidates, contacts and awake
bodies provide workload context. No machine-dependent speed threshold fails tests.

ReleaseFast variants ran in order: baseline, corrected bounds, cached bounds,
then cached bounds, corrected bounds, baseline. Tables below use the second suite
for all ReleaseFast variants and the single Debug suite. Repeat-suite means are
included later, including an outlier; no measured samples were discarded.

Percentiles describe the individual updates over evolving scenes, including
scheduling noise. They are not confidence intervals or pure algorithm timings.

## Current runtime: compiler modes

Each scene has 2,000 dynamic bodies; the mixed scene also has four static walls.
Values are milliseconds per actual physics step.

| Workload | Debug mean | Debug p95 | ReleaseFast mean | ReleaseFast p95 |
|---|---:|---:|---:|---:|
| Sparse moving circles | 1.278 | 1.315 | 0.090 | 0.100 |
| Dense circle cloud | 9.685 | 10.922 | 1.003 | 1.051 |
| Mixed enclosure, sleeping disabled | 43.164 | 59.748 | 5.919 | 8.329 |

A 60 Hz frame budget is 16.67 ms for the entire application. These measurements
exclude scene logic, rendering, graphics synchronization and editor UI. Catch-up
frames may execute more than one physics step.

Sparse circles start on an 80-unit grid and translate together. Dense circles
start overlapping in a 500x500 region and use eight position iterations, zero
gravity and disabled sleeping. Mixed shapes start at random positions inside a
1000x1000 enclosure, use gravity 980 and four position iterations, and initially
have velocities in [-200, 200] on each axis. Other settings retain defaults.
These setups and sample windows differ from the older benchmarks.

## Temporary experiment 1: correct rectangle bounds

The rectangle AABB's maximum starts at positive `floatMin(f32)`. For corners
entirely below zero, that incorrectly stretches the box toward the origin.
The experiment changes this initializer to `-floatMax(f32)` on both axes.

The isolated fixture has 128 separated rotated rectangles. Translating it by
whole hash cells into negative coordinates should still produce zero pairs.

| Placement | Baseline mean (ms) | Corrected mean (ms) | Baseline pairs | Corrected pairs |
|---|---:|---:|---:|---:|
| 128 rectangles, positive coordinates | 0.0290 | 0.0240 | 0.0 | 0.0 |
| 128 rectangles, negative coordinates | 12.6112 | 0.0239 | 8128.0 | 0.0 |

The roughly 500-fold improvement in the negative fixture removes erroneous work;
it is not a general physics speedup.

## Temporary experiment 2: cache bounds during broadphase

On top of corrected bounds, each spatial-hash cell stores `{ body, bounds }`.
Bounds are computed once per body per rebuild and reused for pair filtering,
instead of recalculating rotated rectangle corners for every candidate pair.
They are rebuilt on every update, before collision resolution moves bodies.

The corrected and cached variants have matching final-state hashes and matching
reported pair/contact/awake counts for every scenario. Compare those two variants
to isolate the caching change: correcting bounds alone changes the crowded
simulation's trajectory once bodies leave the initially positive arena.

| Workload | Corrected mean (ms) | Cached mean (ms) | Corrected p95 (ms) | Cached p95 (ms) |
|---|---:|---:|---:|---:|
| Sparse moving circles | 0.0905 | 0.1077 | 0.1010 | 0.1148 |
| Dense circle cloud | 1.0037 | 0.8305 | 1.0540 | 1.4227 |
| Mixed enclosure, sleeping disabled | 5.8708 | 4.1422 | 8.3245 | 5.7968 |
| Mixed enclosure, sleeping enabled | 5.8845 | 4.0130 | 8.3357 | 5.7096 |

Caching is a promising experiment, not a universal improvement. In particular,
the sparse scene regresses and the dense-circle p95 is worse even though its mean
improves. On this platform each cell entry grows from 8 to 24 bytes. Measured
post-warm-up allocation growth for the awake mixed case increases from 887,272
to 952,608 bytes per run. A shared bounds array with cell indices is another
implementation worth measuring before adopting this representation.

## Correctness observations and validation

- Existing `zig build test`: 17/17 pass.
- New `zig build bench -Doptimize=ReleaseFast`: 6/6 benchmark sanity checks pass.
- Both complete ReleaseFast suites pass for all three runtime variants.
- The three selected Debug workloads pass and have matching final-state hashes
  with the baseline ReleaseFast version.
- Two temporary regression tests fail on baseline and pass on both corrected
  variants: 1,000 seeded rotated AABBs versus analytic extents; and spatial-hash
  pairs versus an all-pairs oracle, including rotated rectangles, circles,
  static/kinematic filtering, duplicate detection, negative coordinates, and
  rebuilds after movement/rotation. These used the test allocator with leak checks.
- After 240 simulated steps, the baseline awake enclosure has 639 body centers
  outside its interior bounds. The corrected/cached versions both have 643.
  The sleeping-enabled cases have 636 and 649 respectively. Sleeping accounts
  for only about 17 of 2,000 bodies on average during measurement.
- A separate containment diagnostic confirms 529 baseline bodies are beyond
  even the outer wall boundaries, rather than merely penetrating the inner edge.
  Dynamic centers range from x=-291.8 to 1686.5 and y=1076.2 to 5954.6 after four
  simulated seconds; the arena interior is [200,1200] on each axis.

Passing the benchmark means its timing and finite-state checks succeeded; it does
not mean collision containment or response is correct. Containment needs a focused
regression test and investigation before these scenes represent stable stacks.
The force/wake-up and kinematic-contact issues were not changed in this experiment.

## Repeat-suite means

Milliseconds per update. Each entry summarizes 900 measured updates; full-physics
updates each execute one step. Broadphase-only entries execute no simulation steps.

| Variant | Workload | Suite 1 mean | Suite 2 mean |
|---|---|---:|---:|
| baseline | Sparse moving circles | 0.0894 | 0.0898 |
| baseline | Dense circle cloud | 1.0044 | 1.0028 |
| baseline | Mixed enclosure, sleeping disabled | 5.9387 | 5.9194 |
| baseline | Mixed enclosure, sleeping enabled | 5.9229 | 5.9308 |
| baseline | 128 rectangles, positive coordinates | 0.0291 | 0.0290 |
| baseline | 128 rectangles, negative coordinates | 12.6639 | 12.6112 |
| bounds | Sparse moving circles | 0.0897 | 0.0905 |
| bounds | Dense circle cloud | 1.0047 | 1.0037 |
| bounds | Mixed enclosure, sleeping disabled | 7.5325 | 5.8708 |
| bounds | Mixed enclosure, sleeping enabled | 6.0447 | 5.8845 |
| bounds | 128 rectangles, positive coordinates | 0.0241 | 0.0240 |
| bounds | 128 rectangles, negative coordinates | 0.0239 | 0.0239 |
| cached | Sparse moving circles | 0.1202 | 0.1077 |
| cached | Dense circle cloud | 0.8083 | 0.8305 |
| cached | Mixed enclosure, sleeping disabled | 4.1053 | 4.1422 |
| cached | Mixed enclosure, sleeping enabled | 4.1362 | 4.0130 |
| cached | 128 rectangles, positive coordinates | 0.0063 | 0.0070 |
| cached | 128 rectangles, negative coordinates | 0.0062 | 0.0062 |

The first bounds-corrected awake run contains one 1,489 ms wall-clock sample,
which raises that suite's mean to 7.53 ms. Its median is 5.50 ms and p95 8.39 ms.
The second suite's mean is 5.87 ms. The interruption's cause was not identified;
this illustrates why a single average is insufficient on a shared machine.

## Reproduce the baseline

```sh
zig build bench -Doptimize=ReleaseFast
```

For fixed CPU affinity and compilation outside the measurement process:

```sh
zig test src/bench_runner.zig -O ReleaseFast --test-filter 'benchmark:' \
  --test-no-exec -femit-bin=/tmp/zixel-bench
taskset -c 0 /tmp/zixel-bench
```

The runtime corrections and caching prototype were applied only to temporary
copies. The repository retains the benchmark harness, build target, and these
notes. No runtime optimization or bug fix is implied by running the baseline.
