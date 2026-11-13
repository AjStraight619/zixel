# Zixel

A Zig game runtime and editor, currently developed with **Zig 0.16.0**.
The compiler requirement is declared in `build.zig.zon`. Use Zig 0.16.0
for this revision. Dependencies are pinned by commit and package hash.

## Build and run

```sh
zig version                 # should print 0.16.0
zig build                   # editor, CLI, and all samples
zig build test
zig build run -- /path/to/project
zig build run-physics-example
zig build cli -- version
```

Binaries are installed in `zig-out/bin`. The native Linux graphics targets need
the development libraries for ALSA, OpenGL, X11, Xi, and Xcursor when building.
On startup the editor creates any missing project folders, plus
`settings/project.json` and `assets/scenes/main.json` if they do not exist yet.
Existing files are left untouched.

`zig build run` launches the editor; `zig build editor` is an alias.
Both accept a project path after `--`, defaulting to the current directory.

```sh
zig build run -- /path/to/project --log-file editor.log --debug-log zixel_physics
```

- `--log-file <path>` appends every log record to a file as well as stderr and
  the editor console. The file's directory must exist, and one process owns a
  log file at a time.
- `--debug-log <scope>` enables debug records for one scope and may be repeated.
  Scopes in use: `zixel_editor`, `zixel_scene`, `zixel_physics`, `zixel_nav`,
  `zixel_sokol`.

Runtime modules log through `std.log.scoped`, so a game chooses its own output
with `std_options` (`logFn`, `log_level`, `log_scope_levels`). `zixel.logging.Logger`
is the optional sink the editor uses. In Debug builds the default `std.log`
level prints the physics statistics line every `debug_log_interval` steps; set
that field to 0, or raise the level for `.zixel_physics`, to silence it.

`zig build cli -- new my-game` creates a game project that depends on this
checkout (the location recorded when the CLI was built). It refuses to write
into a non-empty directory.

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

- `src/root.zig`: public runtime entry point used by games and the editor.
- `src/engine.zig` and `src/engine/`: engine lifecycle, scenes, entity storage, and rendering.
- `src/physics.zig` and `src/physics/`: simulation, bodies, and collision APIs.
- `src/math.zig` and `src/math/`: vectors, bounds, and shape definitions.
- `src/core.zig` and `src/core/`: reusable support code; `core/nav.zig` exposes navigation.
- `editor/`: editor application, panels, toolbar, and dialogs.
- `cli/`: command-line application (`help`, `version`, `new <name>`).
- `samples/`: runnable games demonstrating the runtime API.

Namespace entry files explicitly export their public declarations. The root also
exports common types directly: `zixel.Engine` and `zixel.engine.Engine` refer to
the same type, as do `zixel.Physics` and `zixel.physics.Physics`.

The application draws the stateless `editor/toolbar.zig`; its supporting modules
live in `editor/toolbar/`. Editor state does not import the toolbar.
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

A scene object is created with the engine's allocator and wrapped by
`Scene.init`. When the scene is removed the engine calls its
`deinit(self, alloc)` and then destroys the object, so `deinit` frees only what
the scene owns and must not call `alloc.destroy(self)`.

Body iterators borrow storage. Do not spawn or remove entities during a physics
update. Rendering is independent of simulation, so paused worlds remain drawable.
Bodies still live inside entities; this extraction preserves the existing simulation
and does not introduce an ECS or separate body storage.

## Naming

Follow the [Zig 0.16 naming guide](https://ziglang.org/documentation/0.16.0/#Names)
and the standard library's layout:

- Files with top-level instance fields use `TitleCase`, such as `Engine.zig` and
  `Vec2.zig`. The file itself represents the type.
- Namespace files use `snake_case`, such as `physics.zig`, `narrowphase.zig`, and
  `play_controls.zig`. A namespace can contain types without becoming a type file.
- Types and functions returning types use `TitleCase`. Other functions use
  `camelCase`. Values, including constants and struct fields, use `snake_case`.
  For example, the pathfinding sentinel is `astar.no_parent`. Acronyms follow
  the same rules: `Aabb`, not `AABB`.
- General grouping directories use `snake_case`. Namespace entry files sit beside
  matching directories when they have supporting files: `physics.zig` and `physics/`.
- Type-specific supporting directories can match the type's casing, following
  the standard library's `Io.zig` and `Io/`, or `Io/Reader.zig` and `Io/Reader/`.
  Create these when splitting a type's implementation, rather than capitalizing
  every directory containing types.
- A directory does not create a Zig namespace or establish runtime ownership.
  Imports and public declarations establish the API; fields and lifecycle code
  establish ownership. Implementation files import their dependencies directly
  instead of importing the public entry point back into its own implementation.

For example, the toolbar uses this layout:

```text
editor/
  Editor.zig
  toolbar.zig
  toolbar/
    file.zig
    file/
      NewSceneDialog.zig
    asset.zig
    view.zig
    play_controls.zig
```

The renderer's `owns_pass` field describes whether it controls the graphics pass;
the editor sets it to false because the application controls that pass. Fields
are not made private by adding an underscore prefix.

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

## Entity user data

Game data attached to an entity belongs to the entity, not to the scene that
attached it. `user_data` is a plain field; the world releases it when the
entity is removed, so data on a persistent entity survives scene changes:

```zig
const Stats = struct { health: i32 = 100, coins: u32 = 0 };

const player = world.get(handle).?;
player.user_data = try .init(world.alloc, Stats, .{});
if (player.user_data.as(Stats)) |stats| stats.coins += 1;
```

Allocate with the world's allocator, since that is what releases the data. If
the type declares `pub fn deinit(self: *T, alloc: Allocator) void`, it runs on
release. `as` returns null when there is no data or it was stored as a
different type. Assigning over existing data does not release it; call
`player.user_data.deinit(world.alloc)` first. User data is not part of
`EntityDef` and is not saved with a scene.

## Editor binaries

Editor binaries are specific to an OS and architecture and may require system
libraries. Zig is only needed to build Zixel or compile game code, not to launch
a prebuilt editor.
