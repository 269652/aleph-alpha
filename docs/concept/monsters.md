# Monsters: folklore with a real animal underneath

A roster of hostile, non-ordinary creatures, and the art brief for drawing
them. This doc exists because a bestiary bolted onto this game would
contradict a rule the project has already committed to, and the interesting
design is in *not* contradicting it.

## The rule this has to obey

[worldbosses.md](worldbosses.md) rejects hand-placed encounters outright —
*"No hand-designed 'boss room.'"* — and
[ecosystem_dynamics.md](ecosystem_dynamics.md) rejects manual per-country
curation of danger. A monster that spawns at fixed coordinates because a
designer put it there is the thing both of those say no to.

So a monster here is one of **three shapes**, and each one already has
machinery waiting for it:

| Tier | What it is | Existing machinery |
|---|---|---|
| **A — hostile fauna** | An ordinary species with a hostile temperament and a real niche. Breeds, starves, and can be wiped out like anything else. | `CreatureInfo` species entry + `CreatureRenderer`'s per-biome pools |
| **B — mythic skin** | A *promoted* individual that cleared the mythic threshold, named by the folklore of its real lat/lon macro-region. | `worldbosses.md`'s `MythicRegion` + `MYTHIC_ROSTER_BY_REGION` |
| **C — place-bound** | Bound to a *kind of place* the world generates (a bog, a scree slope, a worked-out shaft), never to a coordinate. | [underground.md](underground.md), [hydrology.md](hydrology.md) |

Tier C is the one worth stating carefully, because it is the closest to the
rejected shape. "Lives wherever the world made a peat bog" is emergent;
"lives at 52.5°N, 13.4°E" is not. The test is whether a second world with
different terrain produces it somewhere else, or not at all.

### On which folklore

The project already curates folklore respectfully and by macro-region
(Krampus, Kitsune). Two things follow, and the second is a real constraint
rather than a caveat:

- **Prefer folklore that is already public-domain storytelling** — European
  bog-wights, Alpine wyrms, mining knockers — where the culture that owns
  the story treats it as story.
- **Do not skin a monster with a living sacred belief.** Several of the most
  "game-ready" names in circulation (the Wendigo above all) are active
  religious/spiritual beliefs of Indigenous peoples, not free folklore. The
  roster below deliberately stays out of that; if the roster is ever widened
  to a region, widen it with something that region tells as a *tale*.

## The roster

Each entry names the biome that produces it, what real thing it is grounded
in, and — the part that matters — **one behaviour no existing creature
has**. A monster that is just a wolf with more health is not worth the art.

### 1. Moorleiche — the bog-wight (grassland / wetland, Northern Europe)

**Tier C.** A peat bog preserves what falls into it; this one walked back
out. Grounded in real bog bodies (Tollund Man, Lindow Man) — leather-brown
skin, red-stained hair, astonishingly intact.

**Its one behaviour: it does not chase, it *cuts off*.** It walks a straight
line toward where you will be, through water and mire that slow you and not
it. Outrunning it is easy; outrunning it *toward the bog* is how it wins.

Reads at 24px as a hunched brown figure with a too-long neck and a pale
rope around it.

### 2. Rimewolf — Fenris-kin (tundra, Scandinavia)

**Tier B**, and the cleanest fit: `worldbosses.md` already names Fenrir for
Scandinavia, and `wolf` is already a real species with real art. A Rimewolf
is a wolf that outlived and outfought its pack until the mythic threshold
caught it.

**Its one behaviour: it hunts the herd, not you.** It works the same
`herbivore_population` the ecosystem sim runs on, and a region it has been
in for a season is visibly emptier. You find it by noticing the absence.

Reads as a wolf silhouette one-and-a-half times too large, frost on the
guard hairs, breath fog every frame.

### 3. Alp — the night-mare (forest, Germanic)

**Tier C**, bound to deep forest at night. The word *nightmare* is this
creature; it sits on a sleeper's chest and presses.

**Its one behaviour: it is only dangerous while you are not.** It cannot be
hit while you are standing; it approaches only while you rest
([survival.md](survival.md)'s sleep) and drains stamina rather than health.
Waking is the counterplay, and the cost of waking is the rest you lose.

Reads as a small hunched thing, too many joints, enormous flat eyes — under
a pointed cap (the *Alpkappe*; take the cap and it must serve you, which is
a taming hook [taming.md](taming.md) can hang off).

### 4. Tatzelwurm — the clawed worm (mountain, Alpine)

**Tier C**, scree and rockfall. A stout serpent with two forelimbs and no
hind ones — reported in the Alps for centuries, exactly the shape of a
real-world cryptid that never resolved.

**Its one behaviour: it uses the terrain as a weapon.** It strikes from
below the scree and its lunge dislodges the slope, which is real physics the
project already has ([terrain_relief.md](terrain_relief.md),
[geology.md](geology.md)). The fight is about where you stand.

Reads as a thick pale S-curve with two stubby arms and a blunt cat-like
skull.

### 5. Curupira — the game-warden (rainforest, Brazil)

**Tier A/C.** A forest guardian with backwards-pointing feet, so its tracks
lead away from where it went. Brazilian folklore, told as a tale.

**Its one behaviour: it is provoked by *your* ecology.** It ignores a player
who hunts sustainably and hunts a player who has driven the local
`herbivore_population` down — the ecosystem sim is the aggro table. It is
the only creature in the game that reads your footprint rather than your
position.

Reads as a small red-haired figure, feet reversed — the reversal must be
legible in silhouette or the whole idea is invisible.

### 6. Ghul — the grave-thing (desert, Arabian)

**Tier C**, bound to burial ground and caravan route. The origin of the word
*ghoul*: a shapeshifter that haunts wastes and takes the shape of the last
thing it ate.

**Its one behaviour: it enters the roster as something else.** At distance
it renders as an ordinary creature of that biome; the swap happens on
approach. It is the one monster that costs the player their trust in
everything else on the horizon — use sparingly, or the desert becomes
unreadable.

Reads as a hyena-shouldered biped, the wrong number of limbs resolving only
up close.

### 7. Nøkk — the water-horse (ocean / river / pond, Nordic)

**Tier C**, any real standing water [hydrology.md](hydrology.md) generates,
including a village's own dug pond ([village_ponds.md](village_ponds.md)) —
which is a genuinely unsettling consequence worth keeping.

**Its one behaviour: it is beautiful until you touch it.** It idles as a
pale horse at the water's edge and does nothing hostile at all; the attack
only exists once a player mounts or is adjacent. Everything before that is
an idle animation, which is why its idle is the *most* important frame set
it has.

Reads as a white horse with river weed in its mane and hooves that are
slightly wrong.

### 8. Knocker — the Bergmännlein (underground, Cornish / Germanic mining)

**Tier C**, [underground.md](underground.md). Miners' folklore: the knocking
in a shaft is either a warning of a collapse or the thing that causes it,
and the miners' own answer was to leave it food.

**Its one behaviour: it is a hazard before it is an enemy.** It knocks — a
real positional sound ([soundscape.md](soundscape.md)) — and the knocking
precedes a collapse. Leave food and it knocks warnings; ignore it and it
knocks the ceiling down. Hostile only if attacked.

Reads as a squat grey figure with a lamp, the same height as a stone block
so it hides in the wall silhouette.

### 9. Wolpertinger (grassland, Bavarian — deliberately absurd)

**Tier A**, and an [easter_eggs.md](easter_eggs.md) candidate rather than a
threat: a taxidermy joke sold to tourists — a hare with antlers, wings and
fangs.

**Its one behaviour: it is a real chimera in a game that has real DNA.**
[dna.md](dna.md) and [animal_genetics.md](animal_genetics.md) already model
inheritance; a Wolpertinger is the one legitimate excuse to splice visible
traits from four species onto one individual and let the genetics system
actually carry it. Harmless, very rare, and worth a lot to a collector.

## Art brief

### What the pipeline actually eats

Measured from `IllustratedAnimalSprite` and `SpriteSheetSlicer`, not assumed:

- **Side view, facing RIGHT.** `CreatureMarker` sets `sprite.flip_h` for
  left; nothing is drawn facing left.
- **One action per ROW**, frames left to right within it. Rows may differ in
  frame count, and frame widths within a row may differ — `detect_frames`
  finds the bands. Do not force a uniform grid.
- **Solid MAGENTA background (`#FF00FF`), and real gaps between frames.**
  This is the one instruction a sheet cannot survive getting wrong, and it
  is worth knowing exactly why rather than taking it on faith.
  `detect_frames` walks columns and asks whether each is empty, and the
  only pixels it calls empty are **transparent** ones and **pale
  near-neutral dividers** (≥ 0.7 on every channel). *No* opaque backdrop
  qualifies — pure black included. So a "near-black" backdrop reads as
  drawing in every column and the whole sheet slices to a single frame.
  Magenta instead is chroma-keyed to real transparency before any of that
  runs (`chroma_key` / `chroma_key_tolerance`), which is why every sheet
  that actually ships in this repo uses it. It is also the only safe key: it is nowhere near any
  colour in the art, so a generous tolerance swallows the anti-aliased
  silhouette edge without touching the creature. A *black* key cannot —
  measured on a real near-black delivery, keying black at even ±0.08
  deletes a third of the drawing's own pixels.
  - **Frames must be at least 60 px wide** after keying:
    `IllustratedAnimalSprite._slice_bands` passes `min_frame_width` 60 (not
    the slicer's own default 8), and anything narrower is discarded
    silently rather than reported. At ~300 px of drawn content per frame
    there is enormous headroom, but a stray mark in a gap vanishes rather
    than becoming a bogus frame — which is the behaviour you want.
  - With a keyed background and a real gap between frames, **divider lines
    are unnecessary**. If a generator draws them anyway they must be pale
    (≥ 0.7 on every channel, roughly `#B3B3B3` or lighter) and near-
    neutral; a mid-grey border reads as drawing, and because a cell border
    runs the full width of its row, one such line is enough to make every
    column non-empty and collapse the row to one frame.
- **Deliver PNG, never a lossy format.** A lossy WebP/JPEG smears both
  invariants above at once: measured on one delivery, a backdrop painted as
  a flat fill arrived varying from 14 to 42 across the sheet, and the
  divider lines came back mid-grey. Losslessly-compressed PNG or nothing.
- **One consistent ground-contact line across every frame of every row.**
  Frames are re-composited onto one canvas with the contact row landing on
  `BASELINE_Y`. A frame whose feet float re-composites wrong.
- **No drop shadows that bleed between cells** — they merge two frames into
  one band and the row slices to garbage.
- **Draw big.** Existing frames measure ~300×290px each. On screen a
  `world_scale` 1.0 species is `BASE_WORLD_WIDTH` = 24 world px ≈ 96 art px
  (`ART_TILE_SIZE` 64 per 16-unit tile = 4 art px per world unit), so the
  sheet is downscaled hard. Detail survives; a thin outline does not.

### Which rows the engine consumes today

**Every row in the skeleton below has somewhere to land except `defend`.**
Measured from the code rather than from the class header, which had drifted:

Declaring the band is the whole integration. `has_action` and
`_build_textures` both key off `"<action>_bands"` generically, so a sheet
entry carrying `attack_bands`, `hurt_bands` or `death_bands` slices and
plays with no further edit — `IllustratedAnimalSprite.declared_actions()`
reads the rows straight off those keys.

| Row | Asked for by | With no art of its own |
| --- | --- | --- |
| `idle` | a creature that has stopped | dedicated row → eat frame 0 → walk frame 0 |
| `walk` | movement, paced by ground covered | — (every sheet has one) |
| `eat` | grazing, browsing, carrion | falls through to `ProceduralAnimalAnimation` |
| `swim` | standing in river, lake or ocean | the walk cycle |
| `drink` | at water, thirsty | whatever `idle` resolves to |
| `attack` | `CreatureMarker`'s predator strike | the walk cycle |
| `hurt` | a survivable hit (`take_damage`) | **nothing — the row is skipped** |
| `death` | the killing blow (`_die`) | **nothing — the marker frees at once** |
| `defend` | *nobody yet* | no `defend` action exists |

The two one-shot rows, `hurt` and `death`, deliberately have **no
fallback** (see `ONE_SHOT_ACTIONS`). A flinch borrowed from the walk cycle
reads as a stumble rather than as a hit landing, and a death borrowed from
any cycling row would never end, so the body would never settle and the
carcass that replaces it would never land. Absent beats approximated: with
no art, a hit flinches nothing and a death frees the marker in the same
frame it always did.

What a one-shot row gets that a cycle does not:

- It plays **through once**, off its own clock started at the moment of the
  event — not the shared `_elapsed_time` every cycling action reads, so a
  flinch that begins mid-cycle still starts at frame 0, and a second hit
  restarts it rather than inheriting the first's remaining time.
- `death` additionally **stops on its final frame** (`HOLDS_LAST_FRAME_ACTIONS`)
  — the pose the body comes to rest in, rendered for a real step before the
  carcass replaces it. A wrapping row would put the corpse back on its feet
  for exactly that step.
- While a death row plays the creature does **nothing else**: no AI, no
  movement, no growth, no disease tick, and it cannot be killed again. The
  death is still **booked against the region on the killing blow**, never
  at the end of the row — a death that only lands when an animation
  finishes is one a chunk unload mid-collapse would lose outright.

`defend` is the one row with nowhere to go: there is no defending state in
`CreatureMarker` at all. Draw it anyway if the sheet is being commissioned
— art outlives the wiring — but expect it to sit unused until a monster
needs a real brace-and-hold behaviour.

### The prompt skeleton

Fill the four bracketed slots. Everything else is pipeline, and changing it
breaks the slicer.

> A sprite sheet of **[CREATURE]** for a 2D game, drawn in **side view,
> facing right**, in a painterly hand-illustrated style with clean readable
> silhouettes and no text or labels.
>
> Solid pure magenta background (#FF00FF), the same magenta everywhere,
> with no gradient or vignette. Each animation is **one horizontal row**;
> separate rows and individual frames with **clear empty magenta gaps**, not
> with drawn borders or boxes. Every frame in every row shares the **same
> ground line** — the feet touch the same height in all of them — and the
> creature is the **same scale** throughout. No drop shadows, no glow,
> nothing crossing a gap. Output as PNG.
>
> Rows, top to bottom:
> 1. **IDLE** — 4 frames, breathing and a small weight shift.
> 2. **WALK** — 8 frames, a full cycle returning to frame 1.
> 3. **EAT** — 6 frames, head down to the ground and back up.
> 4. **ATTACK** — 6 frames: wind-up, commit, strike, follow-through, two
>    recovery.
> 5. **HURT** — 3 frames: impact recoil, stagger, recover.
> 6. **DEATH** — 6 frames, ending in a still pose flat on the ground —
>    the last frame HOLDS while the body rests, so it has to be a settled
>    pose and not a mid-fall one.
>
> **[SILHOUETTE]** — the shape it must read as at thumbnail size.
> **[SURFACE]** — colour, material, texture.
> **[MOTION]** — what its body does that no other creature's does.

`[MOTION]` is the slot that earns the art. "It attacks" produces a generic
lunge from any generator; *"it strikes from below the scree and the slope
slides out from under it"* produces the thing this roster is about.

### Worked prompts

**Moorleiche** — silhouette: *a hunched human figure, neck too long, arms
hanging past the knees, a pale rope collar.* Surface: *leather-brown
peat-tanned skin, red-stained matted hair, waterlogged linen, wet highlights,
peat and reed stuck to the legs.* Motion: *it never runs. The walk is a
straight unhurried trudge that ignores footing; the attack is a slow
two-handed grab that pulls the target toward the water rather than striking.*

**Rimewolf** — silhouette: *a wolf one and a half times too large, shoulders
higher than the skull, tail low.* Surface: *ash-grey guard hairs rimed with
frost, pale blue under-glow in the eyes, breath fog every frame.* Motion:
*a stalking low walk, head level with the spine; the attack is a shoulder
check into a throat-bite, not a leap.*

**Tatzelwurm** — silhouette: *a thick pale S-curve, two stubby forelimbs, no
hind limbs, a blunt cat-like skull.* Surface: *wet limestone-white scales,
grey mottling, a soft pink mouth.* Motion: *it moves by folding and
releasing the S rather than slithering; the attack erupts upward from below
the ground line, and the recovery frames show the scree still falling.*

**Nøkk** — silhouette: *a horse, the proportions faintly too long in the
neck and too short in the legs.* Surface: *wet white coat, river weed woven
into mane and tail, hooves reversed, water sheeting off in every frame.*
Motion: *the idle is calm and genuinely beautiful — standing, grazing,
shaking water from the mane — and the attack is the same animal collapsing
into a lunge with far too many teeth.*

**Curupira** — silhouette: *a small child-sized figure, wild hair, and feet
that point backwards — the reversal must be obvious in pure black.*
Surface: *flame-red hair, deep green-brown skin, forest litter.* Motion:
*it moves fast and low between cover; the attack is a thrown stone or a
spear-thrust, and the walk cycle leaves tracks pointing the wrong way.*

**Knocker** — silhouette: *squat, wide, the height of a stone block, a lamp
in one hand and a pick in the other.* Surface: *grey dust-covered skin, dark
wool, one warm lamp-glow as the only light source on the sprite.* Motion:
*the idle is it striking the wall with the pick — the knock itself; the
attack is reluctant, a backwards swing while retreating.*

**Wolpertinger** — silhouette: *a hare with roe-deer antlers, duck wings
folded on its back and visible fangs.* Surface: *ordinary brown hare fur,
drawn completely straight-faced.* Motion: *idle is a normal hare; the walk
is a normal hop; the "attack" is a half-hearted flutter and a single
unconvincing lunge.*

`EAT` replaced `DEFEND` in this skeleton once the row table above was
measured against the code. They are the two ends of the same mistake: the
engine has no defending state at all, so a DEFEND row slices correctly and
is never asked for, while `eat` is one of only three rows with NO fallback
(`hurt` and `death` are the others) — a species without it drops to
`ProceduralAnimalAnimation` the moment it grazes, which is the exact
art-style swap this whole pipeline exists to stop.

### What NOT to commission

Stock creature sheets sold as "complete" carry rows this engine cannot
reach, and the difference is worth knowing before paying for them. Two
distinct cases:

- **Directional variants** (a DOWN / LEFT / RIGHT / UP set per row) are
  pure waste here, and they are the single most common extra. This engine
  is side-view only: one facing is drawn and `CreatureMarker` sets
  `flip_h` for the other, with `faces_left` declaring which way the supplied
  sheet happens to face (see `IllustratedAnimalSprite`'s own header — that
  is a property of the ASSET, not of the species). A four-direction set
  costs 4× the art for nothing.
- **Actions with no state behind them** — `run`, `throw`, `pick up`,
  `carry`, `cheer`, `sleep`, `defend`. `CreatureMarker`'s whole action
  vocabulary is `walk`, `eat`, `drink`, `swim` and `attack`, plus `idle`
  derived from a standing `walk` and the two one-shot rows. Anything else
  needs a new state in the AI before the band can ever be requested, so
  unlike a row the engine already asks for — where declaring
  `"<action>_bands"` IS the entire integration — these are code, not
  content.

  `sleep` is the cheapest of them by a distance, and worth knowing if a
  sheet includes it anyway: dormancy is already simulated
  (`_step_dormancy`/`_dormant`, real winter hibernation), and that branch
  early-returns without calling `_animation_step` at all, so a dormant
  creature simply freezes on whatever frame it was showing. Setting
  `_current_action = "sleep"` and stepping the animation there is the whole
  job.

### Sizing the sheet

At six rows and 4–8 frames of ~300px each, a sheet lands near **2400×1800**.
Generate each row separately if the generator degrades across a large
canvas — the slicer takes bands per row, so a per-row file with its own
`_bands` entry is equally valid and usually cleaner.

**A hard ceiling, not a preference:** every frame is re-composited onto one
shared `CANVAS_SIZE` of 340×330 with its ground-contact row landing on
`BASELINE_Y` 310. A drawn subject whose content bounding box exceeds that
overflows the canvas outright — `Image.set_pixel` raises on an
out-of-bounds index; it does not silently clip. The largest frame in the
current roster measures 302×293, so ~300×290 of real content per frame is
the working bound.

Apparent size on screen is NOT how big the creature is drawn:
`marker_scale` is `BASE_WORLD_WIDTH (24) * AnimalAnatomy.world_scale /
reference_content_width`, so the drawing is normalized away and
`world_scale` is the only dial (wolf 1.0, Krampus 2.1). Draw big for
detail; size the creature in its anatomy profile.

## Status

- ⬜ Nothing here is implemented. This is a design and art brief; no
  `CreatureInfo` entry, `MythicRegion` roster line or sheet exists yet.
- ✅ **Attack/hurt/death rows are wired** — see "Which rows the engine
  consumes today". `attack` already resolves (to the walk cycle with no
  dedicated art); `hurt` and `death` are one-shot rows with a real state in
  `CreatureMarker`, gated on the art existing so no creature currently in
  the game changes behaviour. Declaring the band is the whole integration.
- ⬜ **No `defend` action exists** — a DEFEND row will slice correctly and
  never be asked for until a braced/guarding state is built.
- ⬜ **No sheet declares `hurt_bands` or `death_bands` yet** — the wiring is
  in place and unexercised until real art lands.
- 🚧 **Tier C's binding rule is stated but not built.** "Bound to a kind of
  place" needs a real predicate per monster (a bog, a scree slope, a worked
  shaft) and those predicates do not all exist yet.
- ✅ **Tier B needs no new mechanism at all** — Rimewolf is a roster line in
  `worldbosses.md`'s existing `MYTHIC_ROSTER_BY_REGION` plus art.
