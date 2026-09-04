# Illustrated art addressing: one file per animation, every season drawn

This doc specifies how illustrated art is organized, found, and fallen back
on, for every kind of subject the game draws — items, placed structures,
and (later) creatures and plants — across every place it is shown, every
season, every state it can be in, and every animation it plays. It grew out
of the wooden club pilot in [item_illustrations.md](item_illustrations.md)
and replaces that pilot's two-rows-in-one-file sheet shape for all NEW art.
It does not invent a new renderer: the slicer, the chroma-key pass, the
divider convention and the season clock all already exist and are reused.

The one-line version: **a drawing's file path is its address, one file holds
exactly one animation, and everything the player sees is drawn — including
every season.** Procedural generation is the fallback of last resort, never
a look.

## Design pillars

1. **Drawn, not generated.** Procedural art has been tried for creatures,
   items, structures, and seasonal tinting, and it has not looked good
   enough to keep. Every subject, in every season and state, is illustrated.
   `ProceduralItemSprite`/`ProceduralStructureSprite`/`ProceduralAnimalSprite`
   remain only as the terminal fallback for a subject with no art at all,
   so a missing file never takes a scene down.
2. **One file, one animation, one row.** A file is a single horizontal strip
   of frames with the existing divider convention. Multi-row sheets are what
   force hand-measured Y bands into every registry entry (see every
   `walk_bands`/`eat_bands` in `illustrated_animal_sprite.gd`); with one row
   per file the band is the whole image and there is nothing to measure.
3. **The path is the address.** Subject, context, season, state and
   animation are directory names. The registry never repeats them; it holds
   only what the pixels cannot say (chroma key, anchor, timing).
4. **Author the base, fill in the rest.** Art arrives incrementally. A
   declared fallback lattice resolves any missing cell to the nearest
   authored one, so a subject with two of fourteen files drawn still renders
   everywhere, and the missing twelve are a checklist, not a blocker.
5. **Composed, not tinted.** Things that sit on top of a subject — lying
   snow, most obviously — are drawn overlay sheets composited at runtime,
   never a recolor. Overlay means composited; it does not mean generated.
6. **Switch on meaning, never crossfade.** Season changes swap files at the
   boundary the season clock already quantises; two pixel-art sheets
   blended together read as a blur, and the tree canopy learned this the
   hard way (seasons.md, "Winter stays bare").

## Precedent in this repo

Nothing below is new in kind. Each rule is something one illustrated class
already does, promoted to the rule for all of them:

| Already proven by | What it proves |
|---|---|
| `horse_walk.png` / `horse_idle.png` / `horse_eat.png` (and deer, boar) | One file per animation, registered as `<action>_path`. The doc comment in `illustrated_animal_sprite.gd` calls this the convention; sheep/wolf/bosses/the club sample are the multi-row exceptions. |
| `IllustratedTree`'s canopy strip | Four DRAWN seasons, picked by meaning off the world clock through one derivation (`TreeRenderer.canopy_state()`), switched at the quantised turn boundary, plus an optional fifth drawn column for snow that is an overlay, not a season. |
| `snow_<level>.png` (snow_cover.md) | Drawn overlay sheets driven by a live world quantity (snow depth), with the set of levels read from whichever files exist. |
| `IllustratedCropSprite` | Separate files per part (`carrot_leaves.png`, `carrot.png`), states as frames within. |
| `IllustratedStoneSprite` / boulders / ore | Variants as a seeded pick among frames of one still sheet. |
| `IllustratedItemSprite` (the club pilot) | An anchor that is a fixed pivot rather than a baseline — the first sheet whose frames had to keep a point in place instead of feet on a line. |

## The address

Every drawing is addressed by five axes, in this fixed order:

| Axis | Vocabulary | Notes |
|---|---|---|
| **subject** | The catalog id: `wooden_club`, `campfire`, `horse`, `cherry` | Matches `Item.sprite_id` for items, so a crafted variant sharing a base item's art keeps working with no second entry. |
| **context** | `icon`, `held`, `placed`, `ground`, `world` | Where it is shown. `icon`: inventory/hotbar/paperdoll/tooltip. `held`: riding `ToolSlot` on the rig. `placed`: built into the world (structures). `ground`: dropped. `world`: a free-standing subject (creature, plant). This is item_illustrations.md's "Surfaces" column made into a key. |
| **season** | `spring`, `summer`, `autumn`, `winter`, `any` | `any` for subjects whose look does not follow the year (a club, every `icon`). A subject declares `seasonal: true` per context; a non-seasonal subject authors one `any` file per state/animation and pays nothing for the axis. |
| **state** | Per subject, declared in the registry with one named **base state** | `pristine`/`worn`/`broken` for a weapon (item_durability.md); `unlit`/`lit`/`embers` for a campfire; `seedling`/`vegetative`/`mature` for a crop. States change what the subject IS; they are drawn. |
| **animation** | Per subject; `still` is the one-frame animation | `attack`, `block`, `burn`, `glow`, `walk`, `eat`, `idle`... Timing (frames per second, loop or one-shot) is registry metadata, not a filename. |

The file path spells the address in that order:

```
assets/sprites/<subject>/<context>/<season>/<state>/<animation>.png
```

For example, a campfire's placed art across the year, plus its
season-invariant icon and its snow overlay:

```
assets/sprites/campfire/placed/summer/unlit/still.png
assets/sprites/campfire/placed/summer/lit/burn.png        8 frames, loops
assets/sprites/campfire/placed/summer/embers/glow.png     4 frames, loops
assets/sprites/campfire/placed/autumn/unlit/still.png
assets/sprites/campfire/placed/autumn/lit/burn.png
assets/sprites/campfire/placed/autumn/embers/glow.png
assets/sprites/campfire/placed/winter/...                 same three
assets/sprites/campfire/placed/spring/...                 same three
assets/sprites/campfire/icon/any/unlit/still.png
assets/sprites/campfire/overlays/snowed.png               drawn overlay, see below
```

Fourteen files for the whole year, each a single row. The directory tree
itself shows what has been authored and what has not.

**File format rules** (unchanged from `ai_sprite_prompts.md`'s ingestion
format, restated as hard rules for anything under this layout):

- One horizontal row of frames. Frames separated by a thin near-white
  divider line, a matching rule around the outer edge, generous padding so
  no drawing touches a rule.
- Solid chroma-key ground (`#FF00FF`) or real alpha; the registry says
  which per subject.
- Frames need not share a width. The slicer finds cells as the runs of
  columns between rules, on the still-opaque image, so an empty-looking
  cell is still a cell.
- Resolution: at least 300px tall; whatever width the frame count needs.

## The registry

`illustrated_art_registry.gd` (new) is a GDScript const dictionary, the
same shape every `_SHEETS` already uses, but keyed by subject and holding
only what the path cannot say:

```
"campfire": {
    "contexts": {
        "placed": {"seasonal": true, "anchor": "footprint"},
        "icon":   {"seasonal": false, "anchor": "center"},
    },
    "base_season": "summer",
    "states": ["unlit", "lit", "embers"],
    "base_state": "unlit",
    "animations": {
        "still": {"fps": 0,  "loop": false},
        "burn":  {"fps": 8,  "loop": true},
        "glow":  {"fps": 4,  "loop": true},
    },
    "overlays": ["snowed"],
    "chroma_key": Color(1, 0, 1), "chroma_key_tolerance": 0.25,   # pure magenta
    "prompt": {...}   # see "Prompts come from the registry"
}
```

Per file, nothing is stored: existence is discovered from the path at
resolve time (the `snow_<level>.png` ladder already works this way), so
dropping in a newly generated season is a file copy and an import, never a
registry edit. A test enumerates the tree and asserts every file present is
addressable (no orphaned typos) and every address the registry implies is
either present or resolvable through the lattice.

**Anchors** are the one thing the pilot proved cannot be shared:

| Anchor | Who | What stays fixed |
|---|---|---|
| `baseline` | Creatures, plants | Feet on a shared line; frame cropped to content, scaled to a shared canvas (`SpriteSheetSlicer.normalize_frames`, as today). |
| `pivot` | Held items | A declared grip point stays at the same cell pixel every frame; the cell is kept whole, never content-cropped (`IllustratedItemSprite`, as today). |
| `footprint` | Placed structures | The cell's bottom edge is the tile's bottom edge; width matches the tile footprint. |
| `center` | Icons | Content-cropped and centered on a square canvas. |

One generic loader slices, keys and anchors by this field. The existing
classes become thin adapters over it rather than each carrying its own copy
of `_slice_bands`.

## Resolution: the fallback lattice

Callers never open files. They ask for an address and get back a
resolution: the frames, the address that actually supplied them, and
whether the answer is the procedural fallback. A missing file resolves in
this order, each step keeping every other axis as requested:

1. **animation → `still`** (a subject with no `burn` cycle yet shows its
   `lit` still).
2. **season → base season** (a campfire with only summer drawn shows summer
   in December).
3. **state → base state** (a campfire with no `embers` art shows `unlit`).
4. **context → `icon`** (ground and held reuse the icon by default, which is
   item_illustrations.md's existing convergence rule, now the fallback
   rather than the only option).
5. **subject → procedural** (`has_*` returns false; the caller draws what it
   draws today).

Season falls back before state on purpose: a state carries gameplay meaning
(embers can be relit; a worn club is about to break) and a season carries
dressing. Showing the right state in the wrong season's art is a wardrobe
error; showing the wrong state in the right season's art misinforms the
player.

Overlays resolve separately and never fall back to a base subject: a
subject with no `snowed` overlay simply carries no snow.

## Seasons: drawn, and switched on the clock

Which season file a subject wears is a pure function of the world clock,
exactly as seasons.md already requires for the ground tint and the canopy
("The canopy is on the clock, not on the simulation"). The resolver takes
its season key from the same quantised derivation (`SeasonCycle` year
fraction through `SeasonTransition.state_at`), so every seasonal subject in
view turns together, on a joined client as much as on the host, with no
per-subject schedule to drift.

- **Hard switch at the turn boundary.** When the quantiser says the season
  has turned, the file swaps. No crossfade.
- **`turning` is a later refinement, not a rule.** The canopy authors a
  distinct "turning" drawing because autumn foliage genuinely is a fifth
  look. A subject that wants the same can declare a `turning_<next>` alias
  that the resolver prefers during the last third of a season; until any
  subject does, the four seasons are the whole vocabulary.
- **Winter files are drawn without snow.** Lying snow is weather, not
  calendar (snow_cover.md); a clear cold December on bare ground must not
  show a snowed campfire. Snow is the overlay below.

## Overlays: drawn layers composited at runtime

An overlay is a drawn sheet, authored per subject, that composites on top
of whichever base frame is active, using the base's own anchor so it lands
where the artist put it. It is driven by a live world quantity rather than
the clock:

| Overlay | Driven by | Precedent |
|---|---|---|
| `snowed` | Snow depth (`EarthChunkManager._snow_depth`, the same source the ground's snow stamps read) | The canopy's optional fifth column; `snow_<level>.png`. Several levels are allowed (`snowed_1.png`, `snowed_2.png`...) and read from whichever exist. |

Overlays are the answer to the combinatorial explosion, not a loophole in
pillar 1: a snow cap on a campfire is one more drawing, composited, rather
than a fourth copy of every animation in every season.

## Prompts come from the registry

`ai_sprite_prompts.md` already writes prompts as separable paragraphs: a
style preamble, a per-kit addendum, a per-subject description, per-state
and per-animation addenda. Those paragraphs move into the registry's
`prompt` block, and a tool (`tools/print_art_prompts.gd`) assembles the
prompt for any address by concatenation. Two consequences:

- The prompt for a cell and the code that loads the cell read the same
  data, so the doc cannot drift from the runtime.
- Seasons use the multi-turn identity technique the doc already recommends
  for bloom stages: generate the base season, then "same object, same
  style, same palette, now in autumn", and so on, so it is recognizably one
  subject across the year. Overlays get their own prompt shape: "only the
  snow, drawn to sit on top of this exact object, on solid magenta".

`ai_sprite_prompts.md` stays as the human-readable rendering of that data
plus the generator-specific advice (Nano Banana's edge softening, the
post-process steps); the per-cell text is generated, not hand-maintained.

## Worked examples

**Wooden club** (non-seasonal, `held` context, anchor `pivot`):

```
assets/sprites/wooden_club/held/any/pristine/attack.png   8 frames, one-shot
assets/sprites/wooden_club/held/any/pristine/block.png    1 frame
assets/sprites/wooden_club/held/any/worn/still.png
assets/sprites/wooden_club/held/any/broken/still.png
```

`icon` falls back to `held/any/pristine/still`, which itself falls back to
the attack cycle's last frame until an icon is drawn. `worn/attack` resolves
to `pristine/attack` (state → base state), which is exactly the pilot's
stated "a worn club still swings using the pristine frames" — now a
lattice rule instead of a per-class special case.

**Campfire** (seasonal, `placed` context, anchor `footprint`): the fourteen
files listed under "The address". While only summer is drawn, every season
resolves to summer and the game is playable; each further season is three
files dropped in.

**A tree** (seasonal, `world` context, anchor `baseline`): maps onto the
address as `cherry/world/<season>/<fruit stage>/still.png` plus a
`snowed` overlay — but is deliberately NOT migrated. The composite tree
sheets work, `IllustratedTree` is heavily tested, and canopy/trunk/fruit are
separately-anchored parts rather than one subject; whether parts become a
sixth axis or a subject each is an open question below.

## Migration

- **Legacy sheets stay registered as they are.** `horse_*.png`, sheep, wolf,
  the bosses, the trees, the crops, the stones: nothing forces a re-slice of
  working art. Their classes become adapters over the generic loader only
  when touched for another reason.
- **New art follows this layout, without exception.** Including regenerated
  replacements for any legacy sheet.
- **The club sample is the first migration.** `wooden_club_combat.png` is
  split by its own painter into the four single-row files above,
  `IllustratedItemSprite` becomes an adapter over the generic resolver, and
  its band-pinning test is deleted because there are no bands.
- **The campfire is the first seasonal, animated structure**, and the first
  subject whose `placed` art is a `Sprite2D` rather than a tile baked into
  `TerrainRenderer`'s atlas (item_illustrations.md, "Placed structures").

## Status / mechanisms

- ⬜ `illustrated_art_registry.gd` — subject declarations, anchors, timing,
  overlays, prompt fragments. Test: every file under `assets/sprites/<subject>/`
  is addressable; every registry-implied address resolves.
- ⬜ `illustrated_art_resolver.gd` — the lattice above, returning
  `{frames, resolved_address, is_procedural}`. Tests pin the fallback order
  (animation, season, state, context, subject) with a fixture tree of
  placeholder files.
- ⬜ Generic single-row loader with `baseline`/`pivot`/`footprint`/`center`
  anchors, built from `SpriteSheetSlicer` and the club pilot's cell-keeping
  path.
- ⬜ Season key from the shared clock derivation; hard switch at the
  quantised boundary.
- ⬜ Overlay compositing (`snowed`), driven by snow depth.
- ⬜ `tools/print_art_prompts.gd`.
- ⬜ Club sample split into four single-row files; `IllustratedItemSprite`
  adapted.
- ⬜ Campfire: fourteen files (summer first), a `Sprite2D` placed surface.
- ⬜ Rendering: `Player`/`CharacterView` drawing held-item animations by
  address; structures drawing placed animations by address.

## Open questions

- **Parts.** Trees are canopy + trunk + fruit, the character is a paperdoll
  of parts. Whether `part` is a sixth axis or each part is its own subject
  (`cherry_canopy`, `cherry_trunk`) is not decided; the tree stays on its
  composite sheet until it is.
- **Facing.** Creatures have a facing axis (`faces_left` per sheet) that
  items and structures do not. The address does not carry it; a `world`
  subject that needs one declares it in the registry the way sheets do
  today. Migrating creatures is out of scope until the item/structure path
  is proven.
- **Variants.** Stones pick a seeded variant among frames of one still.
  Under this layout that is `still.png` with N frames and a `variant_seed`
  pick, no new axis — but it has not been exercised.
- **Memory.** Four seasons of a busy structure is four times the texture
  memory of one. Files load lazily on first resolve; whether off-season
  files are evicted is undecided and probably unnecessary at pixel-art
  sizes.
- **`turning` aliases** beyond the canopy — see Seasons above.
