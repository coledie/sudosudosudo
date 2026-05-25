# Sudoku Kilominx — Design Document

A working log + design reference for putting a Kilominx-style cut pattern onto a dodecahedron in Three.js. This document captures **what we tried, what failed, what we learned, and what the geometry actually is** so the next person (or future me) doesn't repeat the false starts.

The companion file `sudoku-cube-design.md` covers the 9³ cube version. This file is specifically about the dodecahedral / Kilominx variant in `sudoku-kilominx.html`.

---

## 1. What a Kilominx actually is

This was the biggest single thing to get right, and the thing I had wrong on the first three attempts.

- A **Kilominx** is a face-turning dodecahedron twisty puzzle. It's a Megaminx with the edge pieces and centers removed — only the **corner pieces** remain.
- There are **20 physical corner pieces** (one per dodecahedron vertex), each touching **3 adjacent pentagonal faces**.
- On each of the 12 pentagonal faces, you see **5 visible stickers**, one from each of the 5 corner pieces sharing that face.
- 20 pieces × 3 stickers each = 60 stickers = 12 faces × 5 stickers per face. The arithmetic closes cleanly.

### The sticker shape on each face is a kite, not a triangle

This is the key takeaway and the one I got wrong twice. The 5 stickers on a face are **kite-shaped**, not pie-slice triangles. Each kite has 4 vertices:

1. The **face center** `C`
2. The **midpoint of the edge clockwise** of the outer corner (`mPrev`)
3. The **outer dodecahedron vertex** `V`
4. The **midpoint of the edge counter-clockwise** of the outer corner (`mNext`)

The 5 kites tile the pentagon. They meet at the face center `C` along **5 segments going from C to the 5 edge midpoints** — not from C to the vertices. That distinction matters: from-center-to-vertices is the cut pattern of a Pentultimate (edge-turning), not a Kilominx (face-turning).

### Visual identification

If you can see the line from face center to each **edge midpoint**, you're drawing a Kilominx. If you can see the line from face center to each **outer vertex**, you're drawing something else (Pentultimate or similar).

---

## 2. Why face-turning produces this pattern (intuition)

The Kilominx has 12 cut planes, each parallel to one of the 12 pentagonal faces. The cuts are positioned at exactly the depth where adjacent corner pieces meet edge-to-edge — no edge-piece or center-piece slab between them.

When you intersect those 12 cut planes pairwise and look at the resulting surface pattern on any one face, the boundaries between corner stickers are the 5 segments from that face's center to the midpoint of each of its 5 edges. Each "kite-meet" line is where two adjacent face cuts intersect inside the puzzle and emerge on the surface.

You don't actually have to compute the 3D cut planes to render the surface pattern. Once you know the pattern is "5 segments from face center to edge midpoints," you can draw it directly on each pentagonal face. That's the shortcut taken here.

---

## 3. The journey — what we tried and what went wrong

### Attempt 1 — Triangle slices

The first version split each pentagon into 5 triangles by drawing segments from the **face center to each vertex**. It looked clean but it was the wrong puzzle's cut pattern. Plus the slices were inset toward their centroid (creating visible gaps) and lifted off a dark inner dodecahedron core, which made them look like floating triangles rather than face stickers.

**Lessons:**
- Triangles from-center-to-vertices ≠ Kilominx.
- Visible gaps between sticker meshes + dark interior visible through the gaps = "outline of a dodecahedron showing through." That ruined the read of the shape.

### Attempt 2 — Triangles flush against the surface

I removed the dark core, set inset and lift to 0, and let backface culling hide the far side of the dodecahedron. Each pentagon was now divided into 5 triangular regions tiling it perfectly. Visually much better — looked like a real colored dodecahedron — but it was still the **wrong cut pattern** (triangles, not kites).

**Lessons:**
- Tile faces edge-to-edge with no gaps. Don't render an inner body behind the sticker shells; if you do, gaps reveal it.
- Use backface culling (single-sided rendering) for a closed convex polyhedron — there's no need for a solid body inside.

### Attempt 3 — Kite slices

I rewrote the slice geometry to be kites: 4 vertices each `[C, mNext, V, mPrev]`, triangulated as two triangles sharing the `C↔V` diagonal. `EdgesGeometry` automatically suppresses the internal diagonal because adjacent coplanar triangles' shared edges are below the default angle threshold — so the kite renders with 4 outer edges, exactly matching the Kilominx pattern.

This was geometrically correct, but at this point the user wanted to start over cleanly, so we threw it out and rebuilt from a plain dodecahedron.

**Lessons:**
- Kite triangulation: 4 vertices, indices `[0,1,2, 0,2,3]`. `EdgesGeometry` will drop the shared interior edge.
- Vertex winding order for kites laid out as `[C, mNext, V, mPrev]` (going CCW from outside the face) gives the correct outward-pointing front face.

### Attempt 4 — Plain dodecahedron + cut lines

Started over from `THREE.DodecahedronGeometry(2.5)` and added the 60 cut lines as overlay geometry. First as `THREE.LineSegments` (1px lines) — invisible at any practical zoom level because **WebGL doesn't support thick lines in most browsers** (the `linewidth` material property is ignored). Then as **thin rectangular triangle-mesh stripes** (4 verts × 2 tris each) lifted slightly along the face normal. The stripes are real triangle geometry, so they render at any thickness reliably.

**Lessons:**
- `LineBasicMaterial.linewidth > 1` does **not** work in WebGL on Windows/Chrome/Firefox. If you need a line thicker than 1px, build a quad strip.
- Lifting the stripes ~0.012 along the face normal + enabling `polygonOffset` on the material is enough to prevent z-fighting with the underlying face.

### Attempt 5 — Canonical math vs. Three.js's actual vertex layout

The first version of the stripe-on-each-face code computed face centers from canonical dodecahedron math: vertices at `(±1, ±1, ±1)`, `(0, ±1/φ, ±φ)`, `(±1/φ, ±φ, 0)`, `(±φ, 0, ±1/φ)`, and face directions from icosahedron vertices `(0, ±1, ±φ)` etc.

**It didn't line up.** Three.js's `DodecahedronGeometry` uses a vertex layout where the large coordinate is in a different axis than my canonical math:

| | Cube verts | Non-cube verts (each with 4 sign combos) |
|---|---|---|
| **My canonical math** | `(±1, ±1, ±1)` | `(0, ±1/φ, ±φ)`, `(±1/φ, ±φ, 0)`, `(±φ, 0, ±1/φ)` |
| **Three.js** | `(±1, ±1, ±1)` | `(0, ±φ, ±1/φ)`, `(±φ, ±1/φ, 0)`, `(±1/φ, 0, ±φ)` |

Both are valid regular dodecahedra, but they're **rotated relative to each other**. The face centers I computed pointed in different directions than the actual face centers in Three.js's mesh, so the stripes landed in empty space between faces.

**Fix:** stop trusting canonical math against a black-box geometry. Extract face data directly from `geom.attributes.position` — read all triangles, group them into 12 coplanar sets by matching normals (using a 0.01 dot-product tolerance for `1 - n_a · n_b`), then for each group dedupe to find the 5 unique vertices and sort them CCW around the normal. That gives you the actual face centers and edge midpoints in **whichever orientation Three.js happens to use**.

**Lesson — the most important one in this whole project:**
> When overlaying geometry on top of a third-party mesh, derive your reference frames from the mesh you actually have, not from a textbook formula for the same shape.

---

## 4. Final algorithm (what's in `sudoku-kilominx.html` now)

The file is small. The cut-drawing pass is a single IIFE that runs once after the dodecahedron is added to the scene.

### Step 1 — Read all triangles out of `geom`

```js
const pos = geom.attributes.position;
const triCount = pos.count / 3;
const tris = [];
for (let t = 0; t < triCount; t++) {
  const v0 = new THREE.Vector3().fromBufferAttribute(pos, t * 3 + 0);
  const v1 = new THREE.Vector3().fromBufferAttribute(pos, t * 3 + 1);
  const v2 = new THREE.Vector3().fromBufferAttribute(pos, t * 3 + 2);
  const n = new THREE.Vector3().subVectors(v1, v0)
              .cross(new THREE.Vector3().subVectors(v2, v0))
              .normalize();
  tris.push({ vs: [v0, v1, v2], n });
}
```

Three.js stores `DodecahedronGeometry` as 36 triangles (12 faces × 3 triangles per pentagonal fan). No index buffer is used — positions are interleaved per triangle.

### Step 2 — Group triangles by normal direction (12 faces)

```js
const FACE_TOL = 0.01;
const faces = [];
for (const t of tris) {
  let f = faces.find(f => f.normal.dot(t.n) > 1 - FACE_TOL);
  if (!f) { f = { normal: t.n.clone(), tris: [] }; faces.push(f); }
  f.tris.push(t);
}
```

For each triangle, find the existing face whose normal matches within tolerance. If none, start a new face. End state: 12 faces, 3 triangles each.

### Step 3 — Dedupe vertices and sort CCW around the face normal

```js
const KEY = v => `${v.x.toFixed(4)},${v.y.toFixed(4)},${v.z.toFixed(4)}`;
// ...for each face:
const vmap = new Map();
for (const t of f.tris) for (const v of t.vs) {
  const k = KEY(v);
  if (!vmap.has(k)) vmap.set(k, v.clone());
}
const verts = Array.from(vmap.values());        // 5 of them
const center = new THREE.Vector3();
for (const v of verts) center.add(v);
center.multiplyScalar(1 / verts.length);
const u0 = new THREE.Vector3().subVectors(verts[0], center).normalize();
const w  = new THREE.Vector3().crossVectors(f.normal, u0);
verts.sort((a, b) => {
  const ra = new THREE.Vector3().subVectors(a, center);
  const rb = new THREE.Vector3().subVectors(b, center);
  return Math.atan2(ra.dot(w), ra.dot(u0)) - Math.atan2(rb.dot(w), rb.dot(u0));
});
```

String-keyed `Map` dedupe is fast and avoids floating-point near-miss issues if you keep the precision modest (4 decimals here). The angular sort uses two perpendicular in-plane basis vectors `(u0, w)` and `atan2` of the projected radial vector.

### Step 4 — Build 60 cut stripes as a single mesh

```js
const LIFT = 0.012;       // outward lift to sit on top of the face
const HALF_W = 0.03;      // half-thickness of each stripe
const positions = [], indices = [];
let vi = 0;
for (const f of faces) {
  const liftedCenter = f.center.clone().addScaledVector(f.normal, LIFT);
  for (let i = 0; i < 5; i++) {
    const va = f.verts[i];
    const vb = f.verts[(i + 1) % 5];
    const mid = new THREE.Vector3().addVectors(va, vb).multiplyScalar(0.5)
                  .addScaledVector(f.normal, LIFT);
    const along = new THREE.Vector3().subVectors(mid, liftedCenter).normalize();
    const perp  = new THREE.Vector3().crossVectors(f.normal, along)
                    .normalize().multiplyScalar(HALF_W);
    const p0 = liftedCenter.clone().sub(perp);
    const p1 = liftedCenter.clone().add(perp);
    const p2 = mid.clone().add(perp);
    const p3 = mid.clone().sub(perp);
    positions.push(p0.x,p0.y,p0.z, p1.x,p1.y,p1.z, p2.x,p2.y,p2.z, p3.x,p3.y,p3.z);
    indices.push(vi, vi+1, vi+2, vi, vi+2, vi+3);
    vi += 4;
  }
}
```

Each stripe is a rectangle in the face plane: 4 corners, 2 triangles. The `perp` vector is `normal × along`, scaled to half the desired stripe width. All 60 stripes go into one shared `BufferGeometry` — one draw call.

### Step 5 — Material with polygon offset

```js
const cutsMat = new THREE.MeshBasicMaterial({
  color: 0x07060f,
  side: THREE.DoubleSide,
  polygonOffset: true,
  polygonOffsetFactor: -1,
  polygonOffsetUnits: -1,
});
const cutsMesh = new THREE.Mesh(cutsGeom, cutsMat);
cutsMesh.renderOrder = 1;
dod.add(cutsMesh);
```

- `MeshBasicMaterial` so the stripes aren't lit (they should read as flat ink, not shaded).
- `polygonOffset` with negative factor + units pulls the depth toward the camera, killing z-fighting against the underlying face even if the LIFT alone weren't enough.
- `renderOrder = 1` (the dodecahedron renders at the default 0) is belt-and-suspenders for ordering.
- The cut mesh is parented to `dod`, so it rotates with the dodecahedron under right-drag.

---

## 5. Architecture overview

Single HTML file, no build step, Three.js r128 from a CDN. The whole thing is about 110 lines.

1. **DOM/CSS** — body with the same radial-violet gradient the cube version uses, transparent canvas overlay.
2. **Scene + renderer** — `PerspectiveCamera` at `(0, 0, 9)`, antialiased transparent WebGL renderer.
3. **Lighting** — hemisphere + key directional + rim directional. Cool sky, warm key, blue rim. Same studio rig as the cube version.
4. **Dodecahedron mesh** — `MeshStandardMaterial` with `flatShading: true` for crisp face shading. `EdgesGeometry` outline as a child for visible face borders.
5. **Cut overlay** — the IIFE described above, parented to the dodecahedron.
6. **Input** — right-button-drag rotates (mutates `dod.rotation.x/y`); mouse wheel zooms (mutates `camera.position.z` clamped to `[4, 30]`); `contextmenu` is suppressed so the right-click drag doesn't open the system menu.
7. **Render loop** — vanilla `requestAnimationFrame`.

There's intentionally **no cell selection, no digits, no Sudoku state** in this file. The cube version has all of that, and the conversation history walks through how it'd be ported to this geometry (kite-meshes, click-pick on triangles, 72° in-plane snap for digit decals, etc.). This file is the **geometry baseline** that the puzzle features would sit on top of when you're ready.

---

## 6. Tuning knobs

If the cut lines look wrong on your screen, the two constants to play with first are at the top of the cuts IIFE:

| Constant | Default | What it controls |
|---|---:|---|
| `LIFT` | `0.012` | How far the cut stripes float above the face surface along the face normal. Bigger = more obviously raised but more "floating sticker" looking. |
| `HALF_W` | `0.03` | Half the stripe thickness. Total visible cut width is `2 * HALF_W` ≈ 0.06 puzzle-units. |
| `FACE_TOL` | `0.01` | Tolerance for grouping triangles into a single face. Don't raise this above ~0.05 or two different faces will get merged. |

The dodecahedron radius (`THREE.DodecahedronGeometry(2.5)`) and camera distance are tuned together. If you change the radius, you'll likely want to scale `HALF_W` and `LIFT` proportionally.

---

## 7. Hard-won meta-lessons

In rough order of how useful they were:

1. **Know the puzzle before you build the geometry.** A Kilominx is face-turning corners-only; the cut lines run from face center to **edge midpoints**, not vertices. Sketch the pattern on paper before writing any math.

2. **Don't trust canonical formulas against a third-party mesh.** Two valid descriptions of the same regular polyhedron can be rotated 90° apart. Always derive overlay geometry from the mesh you're actually rendering, not from a textbook.

3. **WebGL line thickness is a lie.** If you need anything thicker than 1px, write a quad strip. Don't fight `LineBasicMaterial.linewidth`.

4. **Z-fighting is solved by `polygonOffset`.** A small `LIFT` along the normal helps, but `polygonOffsetFactor: -1, polygonOffsetUnits: -1` on the overlay material is the reliable fix.

5. **Tile faces edge-to-edge with no gaps if you want the shape to read as solid.** Any inset between sub-meshes will reveal whatever is behind them. If there's a darker inner body, the gaps become a "ghost outline" of the shape behind your shape.

6. **Backface culling is free shape-closure.** A convex polyhedron rendered with single-sided materials doesn't need a body mesh inside it — the back faces are culled and the surface reads as opaque.

---


## 8. Going past cubes into new shapes — the design pattern

> Note: sections 4–6 describe an earlier overlay-stripes approach that has since been superseded. The current `sudoku-kilominx.html` builds real 3D kite piece-meshes (one per sticker) and supports corner-grouped selection. This section documents that evolution and generalizes it into a reusable pattern.

The cube version (`sudoku-cube.html`) is a tight, working implementation. The Kilominx is the **first port to a non-rectilinear shape**, and almost every interaction concept in the cube has a clean analog on the dodecahedron — but the geometry pipeline changes in specific, predictable ways. This is the pattern.

### 8.1 The pattern at a glance

| Concern | Cube version | Kilominx version | General pattern |
|---|---|---|---|
| Atomic unit | `BoxGeometry` cube | Kite `BufferGeometry` (4 verts, 2 tris) | One **template geometry** in a canonical local frame |
| Layout | Triple `for` loop in `(i, j, k)` | Triangle-grouping over `geom.attributes.position` | Derive instance transforms **from the actual mesh you're rendering** |
| Instance transform | `position.set(i*s, j*s, k*s)` | `Matrix4.makeBasis(xA, yA, zA).setPosition(C)` | Compose a per-instance basis matrix |
| Per-instance state | `material.emissive`, `userData.value` | `material.emissive`, `userData.corner/siblings` | Per-instance material **clone** so emissive tints are local |
| Selection | Single `Mesh` → `selectCube` | 3 sibling `Mesh`es → `selectPiece` | Selection unit may be **multiple meshes**; group via `userData.siblings` |
| Picking | `raycaster.intersectObjects(allCubes, false)` | `raycaster.intersectObjects(pieces, false)` | Identical raycast pattern; non-recursive so child outlines don't hit |
| Highlight | Layered `EdgesGeometry` scaled up | Pre-shrunk edge-loop in local space | Build a **dedicated highlight geometry**; don't naively scale the body |
| Outline (cuts) | `EdgesGeometry` of `BoxGeometry` | 4 quad strips around the kite edges | Quad strips when you need > 1 px thickness |

### 8.2 The five universal steps when adding a new shape

When extending the design to a Pyraminx, Megaminx, Skewb, Icosahedron, or any other polyhedral puzzle:

1. **Identify the atomic visible piece-type.** What's the *one shape* that appears on the surface, of which the whole puzzle is made? Cube: small cube. Kilominx: kite. Pyraminx: triangle. Megaminx: pentagon + triangle + rhombus (three types — three templates).

2. **Extract real face data from the Three.js primitive.** Don't trust canonical math (`Math.PI / 5`, `(1+√5)/2`, etc.) against `THREE.DodecahedronGeometry` — the two layouts may be rotated relative to each other. Read `geom.attributes.position` triangle-by-triangle, group by normal, dedupe verts via stringified coordinates, sort CCW around the face normal.

3. **Build ONE template piece in a canonical local frame.** Pick a convention (e.g. local `+X` toward the outer vertex, local `+Z` outward face normal, piece lying in local `XY` plane). All instances share this single `BufferGeometry`.

4. **For each instance, compose a basis matrix.** `Matrix4.makeBasis(xA, yA, zA).setPosition(origin)` where the axes are computed from the real face data. Apply with `mesh.applyMatrix4(M)`. This is the universal "place template at slot (face, position)" operation.

5. **Group instances into logical selection units.** Use a string-keyed `Map` on a shared world-space property (in our case, the outer dodec vertex) to find sibling pieces. Store the sibling array in `userData.siblings`. The `select` function then iterates over siblings instead of one mesh.

### 8.3 The four bugs that bit hardest on the cube → kilominx port

These are bugs that **didn't exist in the cube version** because the cube's axis-aligned simplicity hides them. Any new shape will surface them again:

#### Bug 1 — Triangle winding wrong, see-through dodecahedron

Symptom: looking at the front of the shape, you see *through* it to the back-side pieces. Or the front-side pieces are invisible.

Cause: A kite's local 2D layout has `C` at origin, `V` along `+X`, `mNext` at `(+x, +y)`, `mPrev` at `(+x, -y)`. The vertex order `[C, mNext, V, mPrev]` traces **clockwise** when viewed from `+Z` (outside the face), not counter-clockwise. The triangle normals therefore point *into* the dodec, and front-face culling hides the near side.

Fix: reverse the index order — `[0, 2, 1, 0, 3, 2]` instead of `[0, 1, 2, 0, 2, 3]`. Or use `THREE.DoubleSide` if you don't care about cull-correctness.

**Lesson:** for any non-trivial local geometry, draw the winding on paper and verify it traces CCW from outside before writing the indices. Box geometries get this right for free; arbitrary polygons don't.

#### Bug 2 — Inset gaps reveal interior

Symptom: thin gaps between adjacent pieces let you see straight through the hollow shape to the background.

Cause: `INSET > 0` shrinks each surface piece toward its own centroid, leaving narrow gaps. With no body mesh inside, the gaps render as transparent.

Two valid fixes — pick based on aesthetic:
- **Solid look:** `INSET = 0` so pieces tile flush. Best when you want the puzzle to read as a single object.
- **Puzzle-piece look:** keep `INSET > 0` and extrude pieces inward into 3D prisms so each piece is its own solid block. The seams now show dark side-walls, not the background. (See §8.5 for the prism geometry.)

#### Bug 3 — Highlight outline overshoots the piece

Symptom: the selection rim extends past the edge of the dodecahedron on the far side of the piece.

Cause: scaling an edge loop by `mesh.scale.setScalar(1.04)` scales around the **mesh's local origin**, not the geometric centroid of the kite. For a kite whose origin is at `C` (face center) and far vertex `V` is across the kite, scaling 1.04 around `C` shoots `V` outward by 4% — past the dodec edge.

Fix: build a *separate* highlight `BufferGeometry` whose vertices are pre-shrunk toward the kite's own 2D centroid (e.g. by 7%), lifted slightly along `+Z`. No runtime scaling. The highlight then sits cleanly inside the piece on every instance regardless of where local origin happens to be.

**Lesson:** scaling a child mesh in a non-symmetric local frame is almost always wrong. Build the visual element in the same local frame as the body, with the offset baked into vertex positions.

#### Bug 4 — Highlight scale used wrong reference frame

Same root as Bug 3, stated as a general principle: **when overlay geometry needs to be slightly inset or offset from a body, encode the offset into the geometry, not into a transform.** Transforms are good for placement; they're treacherous for sub-pixel visual tuning relative to a parent shape.

### 8.4 Selection: porting `selectCube` → `selectPiece`

The cube version operates on a **single** `Mesh`. The Kilominx version operates on **3 sibling `Mesh`es** (the corner). The shape of `selectPiece` is identical to `selectCube` *modulo a `for` loop over `selectedCorner`*:

```js
// Cube version (paraphrased)
function selectCube(cube) {
  if (selectedCube) {
    selectedCube.material.emissive.setHex(0x000000);
    highlight.parent && highlight.parent.remove(highlight);
  }
  selectedCube = cube;
  if (cube) {
    cube.material.emissive = new THREE.Color(0xffd166);
    cube.add(highlight);
  }
  updateInfo();
}

// Kilominx version (the same pattern, looped over siblings)
function selectPiece(piece) {
  if (selectedCorner) for (const m of selectedCorner) {
    m.material.emissive.setHex(0x000000);
    m.userData.highlight && m.remove(m.userData.highlight);
  }
  selectedCorner = piece ? piece.userData.siblings : null;
  if (selectedCorner) for (const m of selectedCorner) {
    m.material.emissive = new THREE.Color(0xffd166);
    const hl = new THREE.LineSegments(kiteHighlightGeom, highlightMat);
    m.add(hl); m.userData.highlight = hl;
  }
  updateInfo();
}
```

The **single highlight instance shared across selections** trick that works for the cube (`highlight.parent.remove`/`add`) doesn't work when the selection is N meshes — you need N highlight clones, one per sibling, stored in each sibling's `userData.highlight`. Otherwise the highlight Mesh can only be a child of one parent at a time.

### 8.5 When you actually want 3D pieces (sketch)

If you go from flat stickers to physical-looking blocks (Bug 2's "puzzle-piece look"), the template geometry becomes a prism with 8 vertices and 12 triangles instead of 4 vertices and 2 triangles:

- 4 top verts at `z = 0` (the sticker face)
- 4 bottom verts at `z = -DEPTH` (toward dodec interior)
- Top tri winding CCW from `+Z`, bottom tri winding CCW from `-Z` (reversed), 4 side quads CCW from outside the prism

`DEPTH` should be less than the polyhedron's inradius so prisms don't poke through the opposite side. For a dodec of circumradius 2.5 (inradius ~1.85), `DEPTH = 0.5` is safe.

This was tried and reverted — the design currently favors flat stickers tiling flush with `INSET = 0`. The recipe is preserved here so it can be revisited without re-deriving the winding.

### 8.6 What ports cleanly from `sudoku-cube.html` without modification

- The CSS panel system (`#info`, `#selected`, `.panel`, `.dim`, `kbd`, etc.) and the radial-violet body gradient.
- The studio lighting rig (hemisphere + warm key + blue rim).
- The click-vs-drag picker (`Math.hypot(dx, dy) < 5` threshold between mousedown and mouseup).
- The raycast pattern (`raycaster.setFromCamera(ndc, camera); raycaster.intersectObjects(arr, false)`).
- The right-drag rotation (mutating `dod.rotation.x/y` directly) and wheel zoom (mutating `camera.position.z` clamped).
- The structure of `selectX(x)`: clear previous → assign new → apply visual → call `updateInfo()`.

### 8.7 What needs rethinking for any new shape

- **The instance layout loop.** Cube: 3 nested integer loops. Kilominx: face-by-face from extracted geometry. Every new shape needs its own.
- **The selection unit.** Cube: 1 cell = 1 mesh. Kilominx: 1 corner = 3 meshes. Megaminx: 1 corner = 3 pentagonal corner-tiles + 1 triangular corner-tile; 1 edge = 2 tiles. Decide what the user clicks on early.
- **The Sudoku constraints.** The cube has 27 sub-blocks of 27 cells (lines along i, j, k and 3×3×3 mini-cubes). The Kilominx-as-Sudoku-board uses each pentagonal face as a 5-cell block — different alphabet (1–5), different number of blocks, different "row/column" analogs (there are no straight lines around a dodec). The puzzle math is shape-specific and is the *hardest* part to port — it's not a code translation, it's a math redesign.
- **Number/decal orientation.** The cube uses a 6-entry `FACE_DIRS` table with pre-baked 4-quat in-plane choices per face. For the Kilominx you'd want a 12-entry face table with pre-baked 5-quat (72°) in-plane choices.

### 8.8 The one rule that summarizes all of this

> **The puzzle's logical structure and the renderer's geometry are two different things, and you must derive each separately from the actual shape — never from canonical math, never from analogy to the previous shape.**

Cubes hide this because their canonical math, Three.js's `BoxGeometry`, and their puzzle structure (rows/columns/blocks) all coincide on the same axes. Every other shape exposes the gap.

