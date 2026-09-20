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
- **Thin divider lines between cells, solid near-black background.** The
  loader flood-fills the border away; a soft vignette around each cell is
  tolerated (`alpha_threshold`) but a crisp divider is better.
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

`idle`, `walk`, `eat` and `swim` — `_SHEETS` carries `walk_bands`,
`idle_bands`, `eat_bands`, and `IllustratedAnimalSprite`'s own header says
plainly that **there is no attack art for any species** and that it is out
of scope so far.

So **attack / hurt / death rows are new**, and commissioning them is the
cheap half. The engine half is a small, well-shaped extension: add
`attack_bands`/`hurt_bands`/`death_bands` to a sheet's `_SHEETS` entry,
extend `has_action`'s fallback chain, and give `CreatureMarker.
_animation_step` the states to ask for. Draw them anyway — art outlives the
wiring, and the wiring is a day.

### The prompt skeleton

Fill the four bracketed slots. Everything else is pipeline, and changing it
breaks the slicer.

> A sprite sheet of **[CREATURE]** for a 2D game, drawn in **side view,
> facing right**, in a painterly hand-illustrated style with clean readable
> silhouettes and no text or labels.
>
> Solid near-black background (#0a0a0a). Each animation is **one horizontal
> row**; separate rows and individual frames with **thin 2px light divider
> lines**. Every frame in every row shares the **same ground line** — the
> feet touch the same height in all of them — and the creature is the
> **same scale** throughout. No drop shadows, no glow, nothing crossing a
> divider.
>
> Rows, top to bottom:
> 1. **IDLE** — 4 frames, breathing and a small weight shift.
> 2. **WALK** — 8 frames, a full cycle returning to frame 1.
> 3. **ATTACK** — 6 frames: wind-up, commit, strike, follow-through, two
>    recovery.
> 4. **DEFEND** — 4 frames: brace, hold, hold, release.
> 5. **HURT** — 3 frames: impact recoil, stagger, recover.
> 6. **DEATH** — 6 frames, ending in a still pose on the ground.
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

### Sizing the sheet

At six rows and 4–8 frames of ~300px each, a sheet lands near **2400×1800**.
Generate each row separately if the generator degrades across a large
canvas — the slicer takes bands per row, so a per-row file with its own
`_bands` entry is equally valid and usually cleaner.

## Status

- ⬜ Nothing here is implemented. This is a design and art brief; no
  `CreatureInfo` entry, `MythicRegion` roster line or sheet exists yet.
- ⬜ **Attack/hurt/death rows have no engine support** — see "Which rows the
  engine consumes today". The extension is small and named there.
- 🚧 **Tier C's binding rule is stated but not built.** "Bound to a kind of
  place" needs a real predicate per monster (a bog, a scree slope, a worked
  shaft) and those predicates do not all exist yet.
- ✅ **Tier B needs no new mechanism at all** — Rimewolf is a roster line in
  `worldbosses.md`'s existing `MYTHIC_ROSTER_BY_REGION` plus art.
