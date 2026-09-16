# Zixel

A Zig game runtime and editor, currently developed with **Zig 0.16.0**.
The compiler requirement is declared in `build.zig.zon`. Use Zig 0.16.0
for this revision. Dependencies are pinned by commit and package hash.

## Build and run

```sh
zig version                 # should print 0.16.0
zig build                   # editor, CLI, and all samples
zig build test
zig build editor -- /path/to/project
zig build run-physics-example
zig build cli -- version
```

Binaries are installed in `zig-out/bin`. The native Linux graphics targets need
the development libraries for ALSA, OpenGL, X11, Xi, and Xcursor when building.
The editor currently scaffolds its project directory on startup and overwrites
`settings/project.json` and `assets/scenes/main.json`; use a disposable project
until loading existing projects is implemented safely.

`zig build run` currently invokes the empty `src/main.zig` placeholder.
Use the editor or sample commands above to run the graphical application.

## Physics benchmarks

```sh
zig build bench -Doptimize=ReleaseFast
# Direct execution without the graphics build dependencies:
zig test src/bench_runner.zig -O ReleaseFast --test-filter 'benchmark:'
# Unoptimized comparison, limited to the moving-body workloads:
zig test src/bench_runner.zig -O Debug --test-filter 'sparse moving' --test-filter 'dense circle' --test-filter 'always awake'
```

Each scenario starts from the same seed for five independent runs. Each run warms
up for 60 updates and measures 180 updates. Output includes mean, p50/p95/p99,
maximum, and the range of per-run means, in milliseconds per update. Simulation
workloads verify exactly one physics step per update; the two broadphase-only
workloads do not advance simulation. Setup and reporting are outside the timings.
Allocations inside physics are timed; allocation growth excludes setup and warm-up.
The allocator matches the physics sample (`page_allocator`), not the editor's C allocator.

The suite also reports candidate pairs, contacts, awake/sleeping bodies, escaped
body centers, and a final-state hash. It checks finite state and identical results
across repeats of the same scenario. Passing these checks does not establish
correct collision response. An escape count indicates the enclosure workload is
losing bodies, so its timing cannot represent a stable contained pile.

These are headless CPU measurements, excluding game logic, rendering, and editor UI.
Percentiles combine changing simulation states and scheduling noise; they are not
confidence intervals. Compare the same compiler, optimization mode, allocator,
hardware, and workload. See [the experiment report](docs/physics-benchmarks.md).

## Layout

- `src/root.zig`: public runtime API used by games and the editor.
- `src/engine/`: engine lifecycle, scenes, entity storage (`World`), and rendering.
- `src/physics/`: `Physics` simulation, body types, broadphase, and collision response.
- `src/core/` and `src/math/`: algorithms and math primitives.
- `editor/`: editor application, panels, toolbar, and dialogs.
- `cli/`: command-line application (`new` is currently a stub).
- `samples/`: runnable games demonstrating the runtime API.

The application draws the stateless toolbar; editor state does not import it.
World exposes a borrowed body iterator; physics and broadphase consume it without
importing World. Entity drawing lives in `engine/draw_entities.zig`.
CLI parsing and project creation share `cli/NewArgs.zig`.

## Runtime responsibilities

`World` owns entities and generational handles. `Physics` owns simulation settings,
timing, and collision state. Drawing reads entities and sends commands to Renderer.
Engine coordinates them; scenes access `ctx.world`, `ctx.physics`, and `ctx.renderer`.

```zig
var world = zixel.World.init(allocator);
defer world.deinit();
var physics = try zixel.Physics.init(allocator, .{});
defer physics.deinit();

// After spawning entities, advance simulation when desired:
physics.update(world.bodies(), dt);
// Inside an active rendering frame:
zixel.drawEntities(renderer, &world);
```

Body iterators borrow storage. Do not spawn or remove entities during a physics
update. Rendering is independent of simulation, so paused worlds remain drawable.
Bodies still live inside entities; this extraction preserves the existing simulation
and does not introduce an ECS or separate body storage.

## Naming

Files representing instantiated types use `TitleCase` (`Entity.zig`, `Vec2.zig`).
Namespace files use `snake_case` (`narrowphase.zig`, `file_menu.zig`). Functions
use `camelCase`; variables and fields use `snake_case`.

## Entity definitions

`EntityDef` borrows its strings, so literals are valid and the definition has no
`deinit` method. `World.spawn` also borrows those strings; keep their storage alive
until the entity is removed.

Use `Entity.toDef(allocator)` or `EntityDef.clone(allocator)` for a deep copy:

```zig
var snapshot = try entity.toDef(allocator);
defer snapshot.deinit();
// snapshot.value is the EntityDef used for saving or spawning.
```

The returned `OwnedEntityDef` owns its storage. Free it once all users of
`snapshot.value` are finished; do not copy the owner and free it twice.

## Versions and releases

Use Zixel release tags (such as `v0.1.1`) independently of Zig compiler versions.
Record the compiler used in each release's notes and keep published tags immutable.
A Git tag identifies a committed source snapshot; it does not include uncommitted
working changes. `v0.1.0` already exists in this repository.

This branch targets Zig 0.16.0 only. Compiler upgrades update the source and
dependency pins together; no compatibility layer for earlier Zig releases is
maintained. Earlier Git commits remain available for older compiler versions.

Distribute editor binaries per OS and architecture. Editor users do not need Zig
to launch a binary, but may need platform shared libraries. Developers compiling
Zig game code against the runtime need the compiler version for that release.
