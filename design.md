# Sudoku Polyhedra — Design Document

A working log + design reference for putting **Sudoku-style cell layouts onto polyhedral twisty-puzzle cut patterns** in Three.js. The repo contains four shapes — Cube, Kilominx, Megaminx, Icosaminx — built progressively from a single design pattern, then merged into one unified webpage (`index.html`).

This doc captures the pattern, what we tried, what failed, and what the geometry actually is. It is written so that the next shape (Pyraminx, Skewb, Crystal, ...) can be added without re-deriving the recipe.

---

## Part I — The universal pattern

Every shape in this repo is built by the **same five-step recipe**. The shape-specific code is small; the pattern is what carries.

### Step 1 — Identify the atomic visible piece-type(s)

What's the *one shape* (or short list of shapes) that appears on the surface of the puzzle, of which every sticker is an instance?

| Shape | Templates needed |
|---|---|
| Cube (9³ shell) | 1 — small rounded cube |
| Kilominx | 1 — kite |
| Megaminx | 3 — pentagon (center), kite (corner), trapezoid (edge) |
| Icosaminx | 3 — triangle (center), kite (corner), trapezoid (edge) |
| Pyraminx (future) | 2 — triangular tip + triangular edge |
| Skewb (future) | 2 — rhombic center + triangular corner |

A "template" is one congruence class of sticker. The Megaminx has three templates because pentagon, kite, and trapezoid are not congruent to each other — but all 60 corner-kites *are* congruent under the dodecahedron's symmetry group, so they share one template.

### Step 2 — Extract real face data from the Three.js primitive

Don't trust canonical math (`(1+√5)/2`, `Math.PI/5`, etc.) against `THREE.DodecahedronGeometry` or `THREE.IcosahedronGeometry`. The two layouts may be rotated 90° apart from any textbook formula you'd write. Always derive overlay geometry **from the mesh you're actually rendering**.

The pipeline (one shared helper, used by all polyhedral shapes in `index.html`):

```js
function extractPolyhedralFaces(sourceGeom, faceTol = 0.01) {
  // 1. Read all triangles out of geom.attributes.position (respecting index buffer if present).
  // 2. Group triangles by matching normal direction (1 - n_a·n_b < faceTol).
  // 3. Per face: dedupe vertices via stringified coords, sort CCW around the face normal.
  // → returns [{ normal, center, verts (CCW-sorted) }, …]
}
```

This handles every regular polyhedron uniformly: dodec gives 12 faces × 5 verts; icos gives 20 faces × 3 verts. **Cubes don't use this** — `BoxGeometry`'s axis-aligned simplicity hides the canonical-math-vs-Three.js-math gap.

### Step 3 — Build one template `BufferGeometry` per piece-type, in a canonical local frame

Pick a convention and bake it once:

- Local `+Z` = outward face normal. The template lies entirely in the local `XY` plane.
- Local `+X` = the template's **axis of symmetry** (the direction the template "points" toward).
- Each template has its own choice of what `+X` means — see Step 4.

A template is a `BufferGeometry` with at most a handful of vertices and 1–3 triangles. It's shared by every instance.

### Step 4 — Place each instance with a per-instance basis matrix

Same code structure for every shape, every template:

```js
const xA = (anchorPoint − faceCenter).normalize();        // template's +X direction
const yA = new THREE.Vector3().crossVectors(n, xA).normalize();
const M  = new THREE.Matrix4().makeBasis(xA, yA, n).setPosition(faceCenter);
mesh.applyMatrix4(M);
```

The **anchor point** is what differs per template:

| Template | Anchor point | Why |
|---|---|---|
| Kilominx kite (`[C, mNext, V, mPrev]`) | Outer vertex `V` | Kite is symmetric around `C→V` axis |
| Megaminx/Icosaminx corner (`[W, A, V, B]`) | Outer vertex `V` | Same as above |
| Megaminx/Icosaminx edge (`[W_i, B_i, A_{i+1}, W_{i+1}]`) | Outer edge midpoint `M` | Trapezoid is symmetric around the apothem direction `C→M` |
| Megaminx/Icosaminx center | Face's vertex 0 (arbitrary) | Centers are *n*-fold symmetric, so any vertex works |
| Cube cell | Cell position `(i, j, k)` | No rotation — axis-aligned `BoxGeometry` |

The placement matrix is a generic `makeBasis(xA, yA, n).setPosition(C)`; only `xA` changes per template.

### Step 5 — Group instances into logical selection units via shared world-space keys

A selection unit may be **more than one mesh** — a Megaminx corner is 3 stickers, an Icosaminx corner is 5 stickers, a cube cell is 1 mesh. Group them with a string-keyed `Map` on something every sibling agrees on in world space:

| Piece type | Group key | Siblings per group |
|---|---|---|
| Cube cell | `(i, j, k)` | 1 |
| Kilominx corner | `V{outerVertex.x,y,z}` | 3 |
| Megaminx center | `C{faceIndex}` | 1 |
| Megaminx edge | `E{midpoint.x,y,z}` | 2 |
| Megaminx corner | `V{vertex.x,y,z}` | 3 |
| Icosaminx center | `C{faceIndex}` | 1 |
| Icosaminx edge | `E{midpoint.x,y,z}` | 2 |
| Icosaminx corner | `V{vertex.x,y,z}` | **5** (five triangles meet at each icos vertex) |

After hashing, store the sibling array in `userData.siblings` and a stable per-type index in `userData.groupIndex` on every member. The `select` function iterates `siblings` instead of acting on one mesh.

### That's the whole recipe

Read it back as a single algorithm:

1. Decide your templates.
2. `extractPolyhedralFaces(primitive)` → face data.
3. Build each template in its canonical local frame.
4. Per face, per slot, compose a basis matrix and place a mesh instance.
5. Hash instances into sibling groups for selection.

Steps 2, 4, and 5 are **the same code in every polyhedral shape**. Only Step 1 (templates) and Step 3 (template construction) are shape-specific.

---

## Part II — The four canonical shapes

### II.1 — Sudoku Cube (9³ shell)

A 729-cell Sudoku-style cube. Only the outer shell is rendered (486 cells; interior is trimmed because nothing inside is visible).

**Templates**: 1 rounded `BoxGeometry`, shared by all 486 cells.

**The rounded-box trick**: start from a subdivided `BoxGeometry(1, 1, 1, 4, 4, 4)`, push each vertex outward from an inner "core box" so corners and edges round out, then average normals across coincident vertices to get smooth bevels. The math is one helper: `makeRoundedBox(size, radius, segments)`.

**Per-face digit decals**: a `MeshBasicMaterial` plane with a canvas-rendered glyph (`makeNumberSpriteTexture`) sits at `+0.501` along each outward face normal. Each face descriptor pre-bakes **4 quaternions** representing the 4 in-plane 90° orientations of the digit. Every frame, the render loop picks whichever of the 4 puts the digit most upright relative to the camera (`f.upCandidates[k].dot(worldUpLocal)` arg-max). Digits snap to cube-aligned angles rather than free-rotating with the camera.

**Interactions**:
- `1`–`9` set a value on the selected cell. `0` / `⌫` clear. Given cells are immutable.
- `WASD` flip the whole cube by 90° around X or Y, snapping `targetRot` to the nearest right angle (animated via `lerp` at 0.18 per frame).
- `↑↓←→` move the selected cell by 1 in the current screen direction. The current rotation is inverted via quaternion to map screen-space onto cube-local, then the dominant axis becomes the move direction. `Shift` swaps the vertical axis for the Z axis.
- `right-drag` rotates freely.

**Sudoku state**: each cell carries `{ i, j, k, isGiven, value, planes, faces, targetPos }`. Givens are generated with `GIVEN_PROBABILITY = 0.30` at build time.

**Stats**: cells (486 / 729 with the shell trim), 27 sub-blocks, given count, user-entry count.

This is the only shape with full Sudoku-style cell input. The polyhedral shapes are geometry baselines; digits could be ported by following the cube's pattern with a 12-face × 5-quat (Megaminx) or 20-face × 3-quat (Icosaminx) snap table.

### II.2 — Sudoku Kilominx (60 kites, dodecahedron)

A face-turning dodecahedron with edges and centers removed — only the 20 corner pieces remain. Each corner has 3 stickers on 3 adjacent faces, so 20 × 3 = 60 kite stickers = 12 faces × 5 kites per face.

**Templates**: 1 kite, vertices `[C, mNext, V, mPrev]` where:
- `C` = face center
- `V` = outer dodec vertex
- `mNext` = midpoint of the outer edge counter-clockwise from `V`
- `mPrev` = midpoint of the outer edge clockwise from `V`

**Critical sticker-shape distinction**: the Kilominx's cut lines run from face center to **edge midpoints**, *not* to vertices. If you draw center-to-vertex you've built a Pentultimate, not a Kilominx. This was the failure mode for the first three attempts during development — see Part III §1.

**Anchor direction**: local `+X = C→V`. The kite extends from `(0, 0)` (the local origin = face center, where `C` sits) out to `(R, 0)` at `V`, with `mNext` and `mPrev` symmetric around the `+X` axis at `(+x, ±y)`.

**Index order**: `[0, 2, 1, 0, 3, 2]` (reversed from the standard `[0,1,2,0,2,3]`). The vertex order `[C, mNext, V, mPrev]` traces **clockwise** when viewed from `+Z`, so the reversed indices flip the winding to make front faces point outward. See Part III §3 for the analytic shoelace check.

**Grouping**: 3-sibling corner groups, keyed by the world-space coordinates of the outer dodecahedron vertex (`V{x,y,z}`). All three corner-stickers on the same physical corner piece share that key.

**No Sudoku state** — pure geometry + selection.

### II.3 — Sudoku Megaminx (132 stickers, dodecahedron)

A face-turning dodecahedron at "real Megaminx" cut depth. Per face: 1 inner pentagon (center) + 5 corner kites + 5 edge trapezoids = 11 stickers. Total: 12 × 11 = 132 stickers across 62 pieces (12 centers + 30 edges + 20 corners).

**Templates**: 3 — pentagon, kite, trapezoid.

**The cut pattern on a face**:
- Inner pentagon `W_i = INNER_SCALE · V_i` (radial from face center `C` toward outer vertex `V_i`, scaled down). Same orientation as the outer pentagon — *not* rotated 36°.
- From each `W_i`, two cut lines go outward toward `V_i`. They terminate at points `A_i` and `B_i` on the two outer edges meeting at `V_i`, a fraction `CORNER_FRAC` of the way from `V_i` toward each neighbor.
- This divides the annulus into 5 kite corners (`[W_i, A_i, V_i, B_i]`) + 5 trapezoid edges (`[W_i, B_i, A_{i+1}, W_{i+1}]`).

**Tunables**: `INNER_SCALE = 0.42` (small pentagon size), `CORNER_FRAC = 0.34` (where the corner cuts meet the outer edge).

**Anchor directions**: corner `+X = C→V`, edge `+X = C→M` (midpoint of outer edge — which is the apothem direction, 36° rotated from the corner's `+X`). Center `+X` is arbitrary; we use the direction to face's vertex 0.

**Index order**: `[0, 1, 2, 0, 2, 3]` for kite and trapezoid (CCW from `+Z` by analytic shoelace). Fan triangulation for the pentagon.

**Grouping**:
- 12 centers: `C{faceIndex}`, 1 sticker each
- 30 edges: `E{midpoint.x,y,z}`, 2 stickers each (the two adjacent faces compute the same midpoint)
- 20 corners: `V{vertex.x,y,z}`, 3 stickers each

**Color-coded materials per piece type** so types read distinct even before any selection: gold centers, blue edges, violet corners.

### II.4 — Sudoku Icosaminx (140 stickers, icosahedron)

The dual-polyhedron flip: face-turning icosahedron at Megaminx-equivalent cut depth. Per face: 1 inner triangle (center) + 3 corner kites + 3 edge trapezoids = 7 stickers. Total: 20 × 7 = 140 stickers across 62 pieces (20 centers + 30 edges + 12 corners).

**The dodec↔icos swap**:

| | Megaminx (dodec) | Icosaminx (icos) |
|---|---:|---:|
| Faces | 12 pentagons | 20 triangles |
| Vertices | 20 | 12 |
| Edges | 30 | 30 |
| Faces meeting at each vertex | 3 | **5** |
| Centers / Edges / Corners | 12 / 30 / **20** | **20** / 30 / 12 |
| Corner sticker count per piece | 3 | **5** |
| Stickers per face | 11 | 7 |
| Total stickers | 132 | 140 |

**Templates**: 3 — triangle (center), kite (corner), trapezoid (edge). **The kite and trapezoid templates are *structurally identical* to the Megaminx's**, with the same `[W, A, V, B]` and `[W_i, B_i, A_{i+1}, W_{i+1}]` layouts. Only the angles change (120° between adjacent face-vertices instead of 72°). The shoelace check still gives CCW from `+Z`, so the same `[0, 1, 2, 0, 2, 3]` triangulation applies unchanged.

**The center template** changes from pentagon (5 verts) to triangle (3 verts) — a fan triangulation handles both uniformly: `for (let i = 1; i < N_VERTS - 1; i++) idx.push(0, i, i+1)`. With `N_VERTS = 3` this emits one triangle `[0, 1, 2]`; with `N_VERTS = 5` it emits the megaminx pentagon's three.

**Source primitive**: `THREE.IcosahedronGeometry(R, 0)` — each of the 20 triangles is already one face. The `extractPolyhedralFaces` pipeline still runs as a no-op grouping step, preserving the uniform code path. The icos primitive uses an **index buffer** (the dodec doesn't), which is the only place the triangle-extraction loop has to branch.

This shape was the cleanest demonstration of the universal pattern: most of the Megaminx code ported unchanged, with the changes being exactly the four things the recipe identifies as shape-specific (source primitive, per-face vertex count, center template shape, grouping totals).

---

## Part III — Hard-won meta-lessons

In rough order of how useful they were across the four shapes:

### 1. Know the puzzle before you build the geometry

The Kilominx wasted three attempts on the wrong cut pattern (triangles from center to vertices, instead of kites from center to edge midpoints) because nobody verified the geometry against a reference image first. **Sketch the sticker shape on paper. Then write the math.**

Two-second test: does the puzzle's cut pattern run from face-center to **edge midpoints** (Kilominx), **vertices** (Pentultimate), or something more elaborate (Megaminx-family)? Get this right and the rest follows.

### 2. Don't trust canonical formulas against a third-party mesh

Two valid descriptions of the same regular polyhedron can be rotated 90° apart. The Kilominx's first overlay-stripes attempt computed face centers from canonical math `(±1, ±1, ±1)` etc., and the stripes landed in empty space between the actual `DodecahedronGeometry` faces. Fix: **derive overlay geometry from the mesh you're actually rendering**, never from a textbook formula. The `extractPolyhedralFaces` helper bakes this rule in.

### 3. Do the shoelace check on paper before writing indices

For any non-axis-aligned template, the vertex order may trace CW or CCW from `+Z` depending on subtle 2D layout details. Get it wrong and you'll see one of: (a) the near side of the shape transparent, (b) the far side showing through the near side, or (c) lighting reading wrong after `computeVertexNormals` propagates the bad winding.

Two-minute test: write the four (or N) template vertices on paper, compute `2A = Σ(x_i·y_{i+1} − x_{i+1}·y_i)`. Positive → CCW → use `[0,1,2,0,2,3]`. Negative → CW → reverse to `[0,2,1,0,3,2]`. The Kilominx kite is CW (and uses the reversed indices); the Megaminx and Icosaminx kites and trapezoids are CCW (and use the standard ones). Doing this up front cost two minutes per template and saved several debug sessions.

### 4. WebGL line thickness is a lie

`LineBasicMaterial.linewidth > 1` is ignored on Windows/Chrome/Firefox. If you need a line thicker than 1 pixel, build a **quad strip** — 4 verts × 2 triangles per segment, lifted slightly along the face normal. The `makeOutlineGeom(pts2d, halfW, lift)` helper does this generically for any closed polygon.

### 5. Z-fighting is solved by `polygonOffset`

Combine a small `LIFT` along the face normal (~0.004 puzzle-units) with `polygonOffsetFactor: -1, polygonOffsetUnits: -1` on the overlay material. The lift handles most cases; the offset is belt-and-suspenders. Outline meshes share `POLY_OUTLINE_MAT` which has both set.

### 6. Tile faces edge-to-edge with no gaps if you want the shape to read as solid

If a `INSET > 0` shrinks each sticker toward its centroid, the gaps between adjacent stickers reveal whatever is (or isn't) behind them — usually the background, making the puzzle look hollow. Two valid solutions:

- **Solid look** (what we use everywhere): `INSET = 0`, stickers tile flush, dark seams come from the outline-stripe overlay
- **Puzzle-piece look** (sketched in the Kilominx doc, not currently used): keep `INSET > 0` and extrude each sticker into a 3D prism so the seams become solid side-walls

### 7. Backface culling is free shape-closure

A convex polyhedron rendered with single-sided materials doesn't need a body mesh inside it — back faces are culled and the surface reads as opaque. None of our polyhedral shapes have an inner body mesh.

### 8. One shape can have multiple sticker templates

The Megaminx has three; a real Pyraminx Crystal has two; a Bandaged 3×3 has many. Don't assume "shape → template" is 1:1. The instance-placement loop runs per template, and each template is a separate `BufferGeometry`. Mass-instancing remains efficient because each template still backs many instances.

### 9. The `+X` anchor direction is a per-template convention

For *n*-fold-symmetric center stickers it's arbitrary. For corners it's `C→V` (the kite's axis of symmetry). For edges it's `C→M` (the apothem). Picking the right anchor direction per template means the placement basis-matrix is the same `makeBasis(xA, yA, n).setPosition(C)` for every template, with only `xA` changing.

### 10. Highlight outlines should be pre-shrunk geometry, not scaled child meshes

`mesh.scale.setScalar(1.04)` scales around the **mesh's local origin**, not the geometric centroid of the piece. For a kite whose origin is at `C` (face center) and far vertex `V` is across the kite, scaling 1.04 around `C` shoots `V` outward by 4% — past the dodec edge. Build a **separate highlight `BufferGeometry`** whose vertices are pre-shrunk toward the kite's own 2D centroid (helper: `makeHighlightGeom(pts2d, shrink, lift)`). No runtime scaling; sits cleanly inside every instance.

### 11. The "single shared highlight" trick fails for multi-mesh selections

The cube's selection unit is one mesh, so a single highlight `LineSegments` that gets `add`/`remove`d works. The polyhedral shapes' selection units are N meshes (3 for a corner, 5 for an icos corner, etc.) and a single highlight can only be a child of one parent at a time. Fix: clone the highlight per sibling, store the clone in `m.userData.highlight`, and remove it from there on deselect.

### 12. Per-instance material `.clone()` for local emissive tints

Every sticker mesh gets its own cloned `MeshStandardMaterial`. The geometry is shared (one `BufferGeometry` backing all 60 corner kites), but materials are not — otherwise setting `material.emissive` on one piece would tint all 60.

---

## Part IV — The unified app (`index.html`)

All four shapes plug into one framework. The shape-specific code is small; the framework is shared.

### Per-shape interface

Each shape factory (`makeCubeShape`, `makeKilominxShape`, `makeMinxLikeShape({...})`) returns an object with:

```js
{
  name,                  // header text
  subtitle,              // one-liner under the header
  controlsHTML,          // keyboard hint markup
  cameraDistance,        // default camera Z on switch

  install(scene),        // build meshes + add root group to the scene
  uninstall(),           // remove root group + dispose() its materials/geometries
  get pickables(),       // array of meshes the raycaster should hit
  pick(intersection),    // handle a successful click
  clearPick(),           // deselect (called on shape switch)
  selectedInfoHTML(),    // → string injected into #selected
  statsHTML(),           // → string injected into #stats

  keydown(e)?,           // optional keyboard handler; return true if consumed
  frame(dt, t)?,         // optional per-frame animation
  handleDrag(dx, dy)?,   // optional override for right-drag rotation
  handleWheel(deltaY)?,  // optional override for zoom (cube has its own)
}
```

### Shape registry & switching

```js
const SHAPES = [ makeCubeShape(), makeKilominxShape(), megaminxShape, icosaminxShape ];
let activeShape = null, activeShapeIndex = 0;

function switchToShape(i) {
  if (activeShape) activeShape.uninstall();
  activeShapeIndex = ((i % SHAPES.length) + SHAPES.length) % SHAPES.length;
  activeShape = SHAPES[activeShapeIndex];
  activeShape.install(scene);
  camera.position.set(0, 0, activeShape.cameraDistance);
  refreshPanels();
}
```

`disposeGroup(group)` walks the group's tree and calls `.dispose()` on every geometry, material, and texture — the unified file would leak GPU memory on every shape switch without it.

### Navigator UI

The top-left panel's header is a 3-cell flex row: `[ ◀ | Shape Name | ▶ ]`, with a row of 4 dots underneath (gold = active). The `◀` `▶` buttons call `switchToShape(±1)`. Keyboard `[` and `]` do the same (`Arrow` keys are reserved by the cube for cell movement).

### Megaminx + Icosaminx share one factory

`makeMinxLikeShape(opts)` parameterizes everything that differs between the two shapes:

```js
{
  name, subtitle,
  sourceGeomFactory: () => new THREE.DodecahedronGeometry(2.5),  // or IcosahedronGeometry
  totals: { center: 12, edge: 30, corner: 20 },                  // for "Edge 7 / 30" labels
  statLines: [['centers', 12], ['edges', 30], ...],              // stats panel rows
  colors: { center: 0xd4a766, edge: 0x6a7fc8, corner: 0x9f76e0 },
}
```

The per-face vertex count is read from the data: `const N_VERTS = faces[0].verts.length;`. Everything downstream (slot loops, center fan triangulation) is parameterized in N. **This factory is the single cleanest demonstration of the universal pattern in the codebase**: changing four config values converts a face-turning dodecahedron puzzle into a face-turning icosahedron puzzle.

### Shared infrastructure

- Scene, camera, renderer (transparent WebGL with `outputEncoding = sRGBEncoding`)
- Lighting: hemisphere + warm key + blue rim + pink fill
- Raycaster + NDC conversion + click-vs-drag picker (`Math.hypot(dx, dy) < 5` threshold)
- Wheel zoom (cube overrides with its own `zoom` variable so it can snap-flip independently)
- Render loop: `requestAnimationFrame` → call `activeShape.frame(dt, t)` if present → `renderer.render(scene, camera)`

---

## Part V — Adding a new shape

The recipe condensed for the next puzzle:

1. **Sketch the sticker shape on paper.** Verify against a reference image. Get the cut pattern right *before* writing code.
2. **Decide your templates.** One congruence class per template.
3. **Pick the source primitive.** `BoxGeometry`, `DodecahedronGeometry`, `IcosahedronGeometry`, `TetrahedronGeometry`, `OctahedronGeometry`. Or use `PolyhedronGeometry` for snub or bandaged shapes.
4. **Add a factory** alongside `makeCubeShape` / `makeKilominxShape` / `makeMinxLikeShape`. For polyhedra, call `extractPolyhedralFaces(sourceGeom)` and follow the recipe.
5. **For each template, do the shoelace check on paper.** Pick `[0,1,2,0,2,3]` or `[0,2,1,0,3,2]` accordingly.
6. **Wire the per-template highlight + outline geoms** via `makeOutlineGeom(pts2d, halfW, lift)` and `makeHighlightGeom(pts2d, shrink, lift)` — both polygon-generic.
7. **Define the sibling group key** for each piece type. World-space coordinates of whatever feature multiple stickers share (vertex, edge midpoint, face center).
8. **Register the shape** by `SHAPES.push(...)`. The navigator picks it up automatically.

If the shape's pattern matches Megaminx/Icosaminx (1 center + N corners + N edges per face), it's a one-liner — instantiate `makeMinxLikeShape({...})` with the appropriate `sourceGeomFactory`, `totals`, `statLines`, `colors`. The factory handles `N = 3` (triangle face) and `N = 5` (pentagon face) uniformly; it would also handle `N = 4` (quad face — a face-turning cube puzzle with this cut pattern would actually be valid) without any changes.

---

## The one rule that summarizes all of this

> **The puzzle's logical structure and the renderer's geometry are two different things, and you must derive each separately from the actual shape — never from canonical math, never from analogy to the previous shape. But the *recipe* for deriving them is the same every time: identify the templates, extract real face data, build templates in canonical local frames, place each instance via a basis matrix, group instances by shared world-space keys.**

Cubes hide this because their canonical math, Three.js's `BoxGeometry`, and their puzzle structure all coincide on the same axes. Every other shape exposes the gap — and rewards using the recipe.
