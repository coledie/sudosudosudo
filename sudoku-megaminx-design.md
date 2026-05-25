# Sudoku Megaminx — Design Document

A working log + design reference for putting a Megaminx-style cut pattern onto a dodecahedron in Three.js. This builds directly on the patterns established in `sudoku-cube-design.md` (the 9³ cube) and `sudoku-kilominx-design.md` (the corners-only dodec), and is the first file in the series to exercise **three** piece-type templates in a single shape.

If you haven't already, read `sudoku-kilominx-design.md` §8 ("Going past cubes into new shapes — the design pattern") first. The Megaminx is a clean application of that pattern with one new wrinkle: more than one template geometry per shape.

---

## 1. What a Megaminx actually is

This was *not* the failure mode for this file — the failure mode of the Kilominx ("which puzzle am I even drawing?") was solved by reading the design doc carefully before writing any code. But it's worth restating the geometry, because the Megaminx is **not** "Kilominx plus extra pieces" — the cut pattern is fundamentally different.

- A **Megaminx** is a face-turning dodecahedron with three piece types:
  - **12 centers** (one fixed pentagon per face)
  - **30 edges** (one per dodecahedron edge, each touching 2 faces → 2 stickers per edge piece)
  - **20 corners** (one per dodecahedron vertex, each touching 3 faces → 3 stickers per corner piece)
- Total: **62 pieces**, **132 stickers** (12 × 11 per face).
- Per face: 1 center + 5 edge stickers + 5 corner stickers.

### The cut pattern on a face

Looking at one pentagonal face from outside:

- A **small inner pentagon** sits in the middle (the center sticker).
- The inner pentagon's vertices `W_i` are **aligned with** the outer pentagon's vertices `V_i` — i.e., `W_i` lies on the radial line from face center `C` to `V_i`, at fraction `INNER_SCALE` of the distance. **Not rotated 36°** — same orientation as the outer pentagon.
- From each `W_i`, **two cut lines** go outward toward `V_i`. They don't terminate at `V_i` itself; they terminate at points `A_i` and `B_i` that sit on the two outer edges meeting at `V_i`, a fraction `CORNER_FRAC` of the way from `V_i` toward the next vertex.
- This divides the annulus into **5 kite-shaped corner stickers** (one at each outer vertex, vertices `[W_i, A_i, V_i, B_i]`) and **5 trapezoid edge stickers** (one along each outer edge, vertices `[W_i, B_i, A_{i+1}, W_{i+1}]`).

The arithmetic closes: 5 + 5 + 1 = 11 stickers per face × 12 faces = 132 stickers, matching the piece arithmetic above.

### Identifying the cut pattern visually

| You see | Puzzle |
|---|---|
| Lines from face center to **edge midpoints** | Kilominx |
| Lines from face center to outer **vertices** | Pentultimate |
| **Small inner pentagon** + lines from its vertices to points NEAR each outer vertex (forming kite corners + trapezoid edges) | **Megaminx** |
| Inner pentagon + lines from its vertices all the way TO the outer vertices | A wrong / degenerate sketch — gives 5 trapezoidal "edges" with no corner stickers |

The third row is the Megaminx. The fourth row is a common drafting mistake that produces only edges; it's geometrically a "Megaminx without corners" and isn't a real puzzle.

---

## 2. The three templates

The Kilominx is built from **one** template kite. The Megaminx needs **three** templates because there are three congruence classes of sticker shape:

| Template | Per face | Total instances | Vertex layout (local 2D, +X = "outward" reference) |
|---|---:|---:|---|
| Center pentagon | 1 | 12 | 5 verts at `INNER_SCALE · R · (cos 72°i, sin 72°i)` for `i = 0..4` |
| Corner kite | 5 | 60 | 4 verts: `W = (INNER_SCALE·R, 0)`, `A` (+x, −y), `V = (R, 0)`, `B` (+x, +y) |
| Edge trapezoid | 5 | 60 | 4 verts: `W_i` (−y), `B_i` (−y), `A_{i+1}` (+y), `W_{i+1}` (+y) along the +X axis (apothem direction) |

Each template is stored once as a shared `BufferGeometry` and reused by every instance via per-instance basis matrices, exactly like the cube and kilominx files. The only multiplier on memory is the per-instance material clone (so emissive selection tints stay local).

### Why three local frames, not one

The placement convention is:
- For centers: local `+X` = direction from face center to **face's vertex 0**.
- For corners: local `+X` = direction from face center to **the corner's outer vertex `V_i`**.
- For edges: local `+X` = direction from face center to **the edge's midpoint `M_i`**.

The "anchor direction" is different for each template because each template's geometry is naturally symmetric around a different axis. A corner kite is symmetric around the `C→V` axis (which becomes local `+X`). An edge trapezoid is symmetric around the `C→M` axis (apothem direction — 36° rotated from any vertex direction). Center stickers are 5-fold symmetric so any choice works, but using "vertex 0 of the face" keeps the template build code uniform.

This means the **edge template's local frame is rotated 36° relative to the face's "vertex 0" frame**. To build it once and reuse it, I derived its positions in face[0]'s `C→M_0` frame (where `M_0` is the midpoint of `V_0V_1`), not in face[0]'s `C→V_0` frame. The two frames are related by a 36° rotation around the face normal, and choosing the right one bakes the rotation into the template instead of into every placement matrix.

---

## 3. The winding-order trap (solved, but worth recording)

The kilominx design doc devotes Bug 1 (§8.3) to this: in a kite `[C, mNext, V, mPrev]` with `mNext = (+x, +y)`, `mPrev = (+x, −y)`, the trace **clockwise** from `+Z`, and the kilominx file uses index order `[0, 2, 1, 0, 3, 2]` to fix it.

For the Megaminx I checked all three templates analytically via the shoelace formula:

| Template | Vertex order | Signed 2× area (sketch) | Orientation |
|---|---|---|---|
| Center pentagon | 5 verts at increasing angle 0°, 72°, 144°, 216°, 288° | Positive (CCW) | CCW from +Z |
| Corner kite | `[W, A, V, B]` with `A` in −Y half, `B` in +Y half | `2y_A·(R − w) > 0` | CCW from +Z |
| Edge trapezoid | `[W_i, B_i, A_{i+1}, W_{i+1}]` going −Y → −Y → +Y → +Y along +X | Positive (CCW) | CCW from +Z |

All three are CCW from `+Z` (= outward face normal) by construction, so the standard fan / quad triangulation `[0,1,2,0,2,3]` (and `[0,1,2,0,2,3,0,3,4]` for the pentagon) gives front faces pointing **outward**. No index flip needed.

**Lesson — generalizing kilominx Bug 1:**
> When laying out a new template, do the shoelace check on paper before writing the index buffer. The sign tells you whether you need `[0,1,2,0,2,3]` or the reversed `[0,2,1,0,3,2]`. If you skip this and just guess, you'll see one of: (a) the near side of the shape transparent, (b) the far side visible through the near side, or (c) lighting that reads wrong because normals flipped after `computeVertexNormals` propagates the bad winding.

I did this check up front for all three templates, and the file rendered correctly on the first run. The Kilominx file took multiple iterations to land here.

---

## 4. Sibling grouping for selection

Per kilominx §8.4 the selection unit may be more than one mesh. The Megaminx has **three different sibling counts** depending on piece type:

| Piece type | Sticker count | Group key (world-space) |
|---|---:|---|
| Center | 1 | `C{faceIndex}` |
| Edge | 2 | `E{edgeMidpoint.x,y,z}` — both adjacent faces compute the same midpoint |
| Corner | 3 | `V{vertex.x,y,z}` — all three adjacent faces compute the same outer vertex |

The grouping pass is the same as the kilominx's corner-grouping pass: walk all 132 stickers, hash by `groupKey`, then back-assign `userData.siblings` (the array of stickers in this group) and `userData.groupIndex` (a stable 0-based index per piece type, e.g. "corner 7 of 20") to each member.

The selection function generalizes the kilominx's `selectPiece` by reading the type off the first sibling and picking the matching highlight geometry (`centerHighlightGeom`, `edgeHighlightGeom`, or `cornerHighlightGeom`). Per kilominx Bug 3, each sibling gets its **own** highlight `LineSegments` instance attached via `m.userData.highlight` — a single shared highlight mesh would only render on the last sibling it was added to.

---

## 5. Code-level generalizations from the kilominx file

These are the changes from the kilominx file's structure that were needed to support multiple piece types. They form the recipe for "what if the new shape has N templates instead of 1":

### 5.1 Hoist outline + highlight construction into helpers

The kilominx file inlined two stripe-builders specific to the kite. The Megaminx file factors them into `makeOutlineGeom(pts2d, halfW, lift)` and `makeHighlightGeom(pts2d, shrink, lift)`, taking a closed polygon of 2D points. Each template then calls both helpers once after computing its 2D vertex list. This removed about 40 lines of duplicated stripe-builder code.

These helpers are **generic over polygon shape**: pentagon, kite, trapezoid all work. Any future shape with a polygonal sticker (triangle, hexagon, rhombus) can plug straight in.

### 5.2 Add a `type` field to every piece's `userData`

```js
piece.userData = {
  type: 'center' | 'edge' | 'corner',
  face: faceIndex,
  slot: i,
  groupKey: '...',     // shared across siblings
  groupIndex: n,       // stable per-type index, set after grouping
  index: globalIndex,
};
```

The `type` field threads through:
- the selection function (picks the right highlight geometry)
- the info-panel formatter (shows "Center 3 / 12" vs "Edge 17 / 30" vs "Corner 5 / 20")
- per-type styling (color, label pill in the UI)

### 5.3 Per-type total in the UI

`TYPE_TOTAL = { center: 12, edge: 30, corner: 20 }` so the info panel reads `Edge 7 / 30` and not `Edge 7 / 62`. This is the kind of detail that signals "the author understood the structure," and it falls out for free if you wire `groupIndex` correctly.

### 5.4 Separate base materials per piece type

The cube has one base color per `(i, j, k)` block; the kilominx uses one base color uniformly. The Megaminx file uses three base materials (gold center, blue edge, violet corner) so the piece types read as different even before you click anything. Per-instance `.clone()` at placement keeps emissive selection tints local — exactly as in the cube and kilominx.

---

## 6. Hard-won meta-lessons from this port

In addition to the lessons inherited from the kilominx file:

7. **One shape can have multiple sticker templates.** The Megaminx has three; a real-world Bandaged 3×3 has dozens; a Pyraminx Crystal has two. Don't assume "shape → template" is 1:1. The instance-placement loop is per template, and each template is a separate `BufferGeometry`. Mass-instancing remains efficient because each template still backs many instances.

8. **The `+X` anchor direction is a per-template convention.** For 5-fold-symmetric center stickers it's arbitrary. For corners it's `C→V` (the axis of kite symmetry). For edges it's `C→M` (the apothem). Picking the right anchor direction per template means the placement basis-matrix is the same code structure for every template (`makeBasis(xA, yA, n).setPosition(C)`), with only `xA` changing.

9. **Do the shoelace check on paper before writing indices.** Cheaper than debugging an inverted-face render. The kilominx file paid the cost of skipping this; the megaminx file did not.

10. **The grouping pass scales by shape, not by code.** Adding a third piece type to the grouping logic was a one-line change (set `groupKey` differently per template at instance time). The hash-bucket-and-back-assign loop didn't change at all.

---

## 7. Architecture overview (what's in `sudoku-megaminx.html`)

Single HTML file, no build step, Three.js r128 from a CDN. ~430 lines.

1. **DOM/CSS** — same radial-violet body gradient and `.panel` style as the cube and kilominx files. Added `.pill.center / .edge / .corner` colored pills for the piece-type label.
2. **Scene + renderer** — `PerspectiveCamera` at `(0, 0, 9)`, antialiased transparent WebGL renderer.
3. **Lighting** — hemisphere + warm key + blue rim, same as the other two files.
4. **Source geometry** — `THREE.DodecahedronGeometry(2.5)` extracted but **never added to the scene**. The visible body is the 132 sticker meshes themselves.
5. **Templates** — three `BufferGeometry`s built in the IIFE (`centerGeom`, `cornerGeom`, `edgeGeom`), each with a matching outline-stripe geometry and inward-shrunk highlight loop.
6. **Instance placement** — three nested loops over faces × slots, each producing meshes with `userData.type` set.
7. **Sibling grouping** — single hash-bucket pass over all 132 pieces using `groupKey`.
8. **Selection** — picks the matching highlight geometry per piece type; attaches an instance per sibling.
9. **Input** — right-drag rotates `dod.rotation.x/y`, mouse wheel zooms `camera.position.z`, left-click (with drag threshold 5px) picks via raycaster.
10. **Render loop** — vanilla `requestAnimationFrame`. No animation state.

There's intentionally **no Sudoku state yet** — no digits, no constraints, no givens. This file is the **geometry + piece-grouping baseline** that a future Sudoku layer can sit on top of. Adding digits would follow the cube's pattern (per-face `MeshBasicMaterial` planes with the 4-quat in-plane snap from `FACE_DIRS`), generalized to a **12-face table with 5-quat (72°) snaps** per the kilominx doc §8.7.

---

## 8. Tuning knobs

The two constants at the top of the build IIFE control the entire cut pattern across all 132 stickers:

| Constant | Default | What it controls |
|---|---:|---|
| `INNER_SCALE` | `0.42` | Center pentagon size as a fraction of the face's circumradius. Smaller = larger annulus = larger edge/corner stickers. |
| `CORNER_FRAC` | `0.34` | How far from each outer vertex the corner-cut emerges along the two adjacent outer edges. Larger = bigger corner stickers, smaller edge stickers. Must be `< 0.5` (else corner stickers from adjacent vertices would overlap). |

Plus the same shared outline + highlight knobs as the kilominx (`halfW = 0.022`, `lift = 0.004` for outlines; `shrink = 0.08`, `lift = 0.008` for highlights), now passed as helper arguments rather than baked per template.

The dodecahedron radius (`THREE.DodecahedronGeometry(2.5)`) and camera distance are tuned together. If you change the radius, scale the outline `halfW` and `lift` proportionally; `INNER_SCALE` and `CORNER_FRAC` are unitless ratios that don't need rescaling.

---

## 9. What ports from `sudoku-megaminx.html` into a future shape

This file is now the cleanest reference for "shape with N piece templates":

- `makeOutlineGeom(pts2d, halfW, lift)` and `makeHighlightGeom(pts2d, shrink, lift)` are polygon-generic and ready to reuse.
- The build IIFE structure (extract triangles → group by normal → dedupe verts → sort CCW → build N templates → instance loop per template → grouping pass) is the universal recipe.
- The `userData.type` + `userData.groupKey` + `userData.groupIndex` + `userData.siblings` schema scales from 1 to N piece types without code changes — only data changes per template.
- `selectPiece(piece)` already dispatches on `type` to pick the right highlight geometry; adding a fourth piece type is a one-entry change to `HL_GEOM`.

Likely next ports:
- **Pyraminx** (face-turning tetrahedron, 4 piece templates: 4 tips, 6 edges, 4 centers — though "centers" on a Pyraminx are trivial axis pieces). Triangular face + triangular stickers, the simplest shape outside the cube.
- **Pyraminx Crystal** (face-turning dodec, different cut depth from Megaminx). Two templates: large pentagonal piece + triangular piece. Adds the wrinkle that the cut pattern is **not** a Megaminx pattern — different depth, different shapes — but the build pipeline is the same.
- **Skewb** (corner-turning cube, 6 centers + 8 corners). Returns to the cube's frame but introduces non-axis-aligned cut planes for the first time. Templates: rhombic-ish center quads + triangular corner stickers.

---

## 10. The one rule, restated for shape #3

The kilominx doc closed with:

> The puzzle's logical structure and the renderer's geometry are two different things, and you must derive each separately from the actual shape — never from canonical math, never from analogy to the previous shape.

The Megaminx adds a corollary:

> **A single shape may have multiple sticker congruence classes. Template per class, frame per template, anchor direction per frame. The placement matrix, the grouping logic, and the selection dispatch are the parts that stay constant across classes.**

That's the abstraction the cube → kilominx → megaminx progression is converging on.
