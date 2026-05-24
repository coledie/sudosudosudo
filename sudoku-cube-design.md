# Sudoku Cube — Design Document

A 3D, 729-cell variant of Sudoku rendered in the browser with Three.js. This document covers what the game is, how the player interacts with it, and how the code is put together.

---

## 1. Concept

Classic Sudoku is a 9×9 grid divided into nine 3×3 sub-blocks. The Sudoku Cube extends that idea by one dimension:

- **9 × 9 × 9 = 729 cells**, arranged as a cube of small cubes.
- The big cube is partitioned into **27 sub-blocks of 3 × 3 × 3** (the visible "chunks" separated by gaps).
- Each small cube is a cell that can hold a digit 1–9.

The current build is a **visual playground / sandbox**: it generates a puzzle where roughly 30% of cells are pre-filled with random digits ("givens"), and the player can navigate the cube, select cells, and write digits into the empty ones. It does **not** yet generate solvable puzzles or validate Sudoku rules — those are deliberate future work (see §9).

The intent of the visuals is to communicate the **scale** of the structure (almost a thousand cells, twenty-seven sub-blocks) while staying calm enough to play in.

---

## 2. Controls

| Action | Input |
|---|---|
| Select a cube | **Left-click** the cube |
| Free-rotate the cube | **Right-click + drag** |
| Snap-flip 90° to a face | **W** / **A** / **S** / **D** |
| Move selected cube (screen-relative) | **↑ ↓ ← →** |
| Move selected cube along Z (depth) | **Shift + ↑ / ↓** |
| Fill the selected cell | **1** – **9** |
| Clear the selected cell | **0** / **Backspace** / **Delete** |
| Zoom | **Mouse wheel** |

### Notes on the controls

- **Left vs right mouse**: left is *the gentle action* (pick a thing), right is *the spatial action* (move the camera frame). They never conflict.
- **WASD flips**, they don't pan. Each press rounds the current rotation to the nearest 90° and adds another quarter turn on the chosen axis, so repeated presses always cycle through the six face-on views cleanly.
- **Arrow keys are screen-relative.** Up always moves the selected cube *up on the screen*, regardless of how the cube is currently rotated. This is implemented by taking the screen-space direction and transforming it through the inverse of the cube's rotation, then snapping to the nearest grid axis (see §6.3).
- **Number keys are inert when no cube is selected**, and they don't conflict with WASD since the key sets are disjoint.
- **Given cells cannot be overwritten.** Number/clear keypresses on a given are silently ignored.

---

## 3. Visual Language

### 3.1 Palette

The 27 sub-blocks each receive a unique color drawn from a constrained jewel-tone palette. The palette is parameterized by the sub-block's 3D index `(bi, bj, bk)`:

- **Hue** varies primarily with `bi`: three hue bases (teal-blue ≈ 200°, violet ≈ 258°, rose-magenta ≈ 318°), nudged ±14° by `bk`.
- **Saturation** rises with `bk` (32% → 50%).
- **Lightness** varies with `bj` (48% → 62%).

This guarantees 27 distinct values while keeping the whole cube within one cool-jewel family, so the structure reads as a single object rather than a random pile.

### 3.2 Geometry — beveled small cubes

Every small cube has rounded edges and corners. They share **one** geometry instance (cost paid once, used 729 times). The geometry is built by:

1. Starting from a subdivided `BoxGeometry` (4 segments per axis, so each face is a 5×5 vertex grid).
2. For each vertex, computing the nearest point on a smaller "inner box" (the box shrunken inward by the bevel radius), then pushing the vertex outward from that inner point by the bevel radius. Vertices already on a flat face don't move; vertices near edges and corners curve outward into cylinders and spheres.
3. Running `computeVertexNormals()`, then **averaging normals across coincident vertices** with a position-hash pass — `BoxGeometry` creates separate vertex copies for each face, so without this averaging the bevels would render with hard, faceted normals. Averaging gives the smooth shading the rounding needs.

### 3.3 Lighting

A four-light studio rig:

- **Hemisphere light** — cool sky / warm-violet ground, weak ambient gradient.
- **Key directional** — warm cream, above-right-front. The dominant shaper of forms.
- **Rim directional** — cool blue, behind-below-left. Defines silhouettes on the dark side.
- **Fill directional** — pink, weak, from below-front. Lifts the underside.

The lights are tuned to make the **bevels and depth of the stack readable** without flattening the colors.

### 3.4 Background

A CSS radial gradient on `<body>` (deep violet center, near-black edges) showing through a transparent WebGL canvas. This gives the cube an "in space" feel without adding render cost.

### 3.5 Numbers

Numbers are drawn into 128×128 canvases and used as `CanvasTexture` `.map`s on the cube material. Because the texture multiplies with the cube's base color, a near-white canvas leaves the cube color visible everywhere except where the digit is drawn. Two sets of textures exist:

- **Given digits** — dark ink (`#1a1230`).
- **User digits** — blue ink (`#1d4d9c`).

The digit is centered, semi-bold, with a soft drop shadow drawn into the canvas. The same texture is applied to all 6 faces of the small cube, so the digit is visible from any orientation.

### 3.6 Selection feedback

Three cues stacked, so the selected cube is unmissable regardless of view angle:

1. **Emissive boost** on the cube's material (warm gold, low intensity).
2. **Inner gold outline** snug around the cube.
3. **Outer gold outline** slightly larger, with a gently pulsing opacity (sine wave at ~3 rad/s).

The outlines are straight `EdgesGeometry` boxes; they read fine framing the rounded cube.

---

## 4. UI Panels

Three frosted-glass panels overlay the canvas:

- **Top-left (info)** — title, brief description, full keyboard legend.
- **Top-right (stats)** — total cells, sub-blocks, given-clue count, user-entry count. Emphasizes the scale of the puzzle.
- **Bottom-left (selected)** — when a cube is selected: cell coordinates (1-indexed), sub-block coordinates, and current value (color-coded: gold = given, blue = user-entered, dim = empty).

Panels use `backdrop-filter: blur(12px)` with a low-alpha dark background, a faint white border, and a soft shadow.

---

## 5. Architecture overview

Single HTML file. Logical sections, in order:

1. **DOM & CSS** — body gradient, panel styling.
2. **Three.js scene setup** — renderer (transparent, sRGB), camera, lights.
3. **Geometry helpers** — `makeRoundedBox`, `smoothCoincidentNormals`.
4. **Texture factory** — `makeNumberTexture`, the `givenTextures` / `userTextures` lookup tables.
5. **Palette function** — `blockColor(i, j, k)`.
6. **Cube grid construction** — builds the 9³ grid, fills `grid[i][j][k]` and `allCubes`, tallies givens.
7. **Selection highlight objects** — the layered outlines.
8. **State helpers** — `selectCube`, `setCellValue`, `updateInfo`.
9. **Input handlers** — mouse (rotate/pick), touch (drag/tap), wheel (zoom), keyboard (flip / move / digit).
10. **Animation loop** — eased rotation, eased cube positions, glow pulse, camera, render.

No build step, no module system. Three.js is loaded from a CDN.

---

## 6. Key implementation decisions

### 6.1 One geometry, 729 meshes, per-cube materials

Geometry is shared (huge memory win). Materials are per-cube because each cube has its own color and texture map. This is a small per-cube overhead but lets us swap the texture map on a single cube (e.g., when the player types a digit) without disturbing anything else.

### 6.2 Eased rotation via a target

Two pairs of variables: `(rotX, rotY)` — current rotation — and `(targetRotX, targetRotY)` — where the rotation is heading. Each frame:

```js
rotX += (targetRotX - rotX) * 0.18;
rotY += (targetRotY - rotY) * 0.18;
```

WASD writes `targetRot`, the loop chases it. Free-drag writes both at once (so it doesn't immediately spring back). This single mechanism handles both snap-to-face animation and free dragging.

### 6.3 Screen-relative arrow movement

When the player presses an arrow key, we need to translate "up on screen" into "which direction in the cube's local grid."

```js
// Build a quaternion for the target rotation, invert it
_tmpEuler.set(targetRotX, targetRotY, 0, 'XYZ');
_tmpQuat.setFromEuler(_tmpEuler).invert();

// Apply to the screen-space direction
const localDir = new THREE.Vector3(sx, sy, sz).applyQuaternion(_tmpQuat);

// Snap to the nearest cardinal axis in cube-local space
```

Using the *target* rotation (rather than the currently interpolating one) means arrow keys behave correctly even mid-flip — they move in the direction the cube *will* face when the animation settles.

### 6.4 Cube swap (instead of cube slide)

Moving the selected cube `(di, dj, dk)` doesn't push the rest of the grid — it **swaps** with whatever cube currently occupies the destination. We:

1. Swap the two cubes' positions in the `grid[i][j][k]` lookup.
2. Swap their `userData.i/j/k`.
3. Update both of their `userData.targetPos` to the new world positions.

Each cube's actual `Object3D.position` is lerped toward its `targetPos` in the render loop, so both cubes animate to their new homes simultaneously without any extra animation infrastructure.

### 6.5 Click vs. drag disambiguation

On mouse-down we record the cursor position and button. On mouse-up, if the cursor moved less than 5 pixels and it was a left button, we treat it as a click and run a raycast pick. Otherwise nothing happens (any motion was attributed to the right-button drag handler if active). This makes "click to select" reliable without ever firing a stray pick during a drag.

### 6.6 Raycasting

`THREE.Raycaster` against `allCubes` (the flat list of all 729 meshes). Three.js handles the rest; we just need to convert the screen coordinates to NDC. With 729 axis-aligned cubes the cost is negligible at interaction time.

---

## 7. Data model

For every small cube, `cube.userData` holds:

```js
{
  i, j, k,         // grid indices in [0..8]
  targetPos,       // THREE.Vector3 — where the mesh should animate to
  isGiven,         // boolean — locked clue if true
  value,           // 0 = empty, 1–9 = digit
}
```

`grid[i][j][k]` is the inverse lookup — pointer to the cube currently occupying that slot. The two stay in sync through `moveSelected` (the only place either changes).

---

## 8. Performance notes

- **729 meshes** sounds like a lot but each has very few vertices (a 4-segment rounded box) and they share geometry, so the GPU draws them efficiently.
- **One draw call per cube** — we don't use `InstancedMesh` because each cube has its own material (color + texture map). This is the main optimization available if performance becomes an issue: switch to per-instance color and per-instance texture-atlas UVs.
- **No shadows, no post-processing, no env map.** Lighting is direct.
- **Texture cache** — only 19 distinct number textures exist (blank + 9 given + 9 user) regardless of grid size.

The animation loop work is dominated by 729 `position.lerp` calls (negligible).

---

## 9. What's not built yet

Intentional gaps in the current version:

- **No Sudoku rule validation.** Givens are random digits, not part of a valid puzzle. No check is performed when the player enters a digit; no rows/columns/pillars/sub-blocks are marked as invalid.
- **No puzzle generation.** Generating a *valid* 9×9×9 Sudoku is a non-trivial constraint-satisfaction problem and a major piece of work in its own right. The rule set itself isn't even uniquely defined — should the constraint be "every row, column, and pillar has 1–9 unique" plus "every 3³ block has 27 unique digits"? Some other variant? This needs a design decision before implementation.
- **No win condition.** Follows from the above.
- **No save/load.** A round of play vanishes on refresh.
- **No notes / pencil marks.** A real Sudoku UI lets you tentatively note candidates in a cell.
- **No undo.**

---

## 10. Likely extensions

In approximate order of payoff:

1. **Pencil marks** — let the player record candidate digits in a cell (small numbers around the corners of the face) before committing.
2. **Constraint highlighting** — when a cell is selected, dim cubes outside its row, column, pillar, and sub-block, so the relevant constraints are visible. This is high-value for both gameplay and for *teaching* the player what 3D Sudoku constraints look like.
3. **Rule validation** — choose a constraint set, then mark conflicts in real time.
4. **Puzzle generation** — a backtracking generator that produces solvable puzzles with adjustable density of givens.
5. **Undo/redo stack** — straightforward once the data model is stable.
6. **Layer isolation** — a keypress that fades all cubes except one slice, so the player can focus on a single 9×9 plane.
