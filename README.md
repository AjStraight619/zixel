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

## Layout

- `src/root.zig`: public runtime API used by games and the editor.
- `src/engine/`: engine lifecycle, scenes, input, rendering, and entity types.
- `src/physics/`: simulation, broadphase, and collision response.
- `src/core/` and `src/math/`: algorithms and math primitives.
- `editor/`: editor application, panels, toolbar, and dialogs.
- `cli/`: command-line application (`new` is currently a stub).
- `samples/`: runnable games demonstrating the runtime API.

The application draws the stateless toolbar; editor state does not import it.
World and broadphase share `engine/EntitySlot.zig` without importing each other.
CLI parsing and project creation share `cli/NewArgs.zig`.

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
