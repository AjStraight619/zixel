# Zixel

A 2D game engine written in Zig. Early development stage.

## What it is

A basic 2D physics engine built with Zig 0.14 and raylib. Currently has:

- Circle and rectangle physics bodies
- Collision detection (AABB + Separating Axis Theorem (SAT))
- Friction and restitution 
- Debug GUI for visualizing physics
- Input management system

## Building

Requires **Zig 0.14**.

```bash
git clone <https://github.com/AjStraight619/zixel.git>
cd zixel
zig build
```

## Running Tests

```bash
zig build run-physics-tests
```

This opens a physics test suite. Press number keys 0-7 to run different tests, g to toggle debug visualization.

## Current Features

- **Physics**: Circles and rectangles with basic collision response
- **Debug GUI**: Shows collision boundaries, contact points, physics stats
- **Input**: Context-aware input handling (GUI vs game input)
- **Tests**: 8 physics verification scenarios

## Controls

- **g**: Toggle debug panel
- **0-7**: Run physics tests
- **SPACE**: Cycle tests
- **R**: Reset world

## Development Status

Early stage. Core physics works, but missing many features you'd expect in a real game engine (audio, advanced rendering, asset management, etc.).

This is a learning project exploring Zig and physics simulation.

## License

MIT License - see [LICENSE](LICENSE) for details.
