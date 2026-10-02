# Spell VFX: the shader technique layer

The shared rendering-technique toolkit every spell atom's effect draws
with — [pixel_art_engine.md](pixel_art_engine.md)'s exact split, moved from
CPU pixel loops to the GPU: a generator (or an illustrated sheet) says *what*
an atom looks like; this doc specifies *how* it moves, glows and disturbs the
screen once it's cast. Companion to
[magic.md](magic.md)'s "Atom effects render as composite spritemaps" section,
which owns sprite *content* — this doc never touches a single pixel of that
content, only what happens to it in flight.

## Why this exists

Asked directly: *"flesh out the spell graphics engine using custom shaders
for magic effects and instruct me to generate sprite art for all the sprites
you need."*

Two real gaps sat behind that ask, both traceable to the same cause — magic's
own 2026-08-28 spec ("Atom effects render as composite spritemaps") describes
exactly this system and neither half of it had been built:

1. **No shader touches a spell effect at all.** `SpellEffectMarker` animates
   scale and alpha with a plain `Tween` — real motion, but flat: no glow, no
   light, no sense of the world reacting to what just happened. This game
   already has a real shader ecosystem (`TorchGlow`, `WaterShader`,
   `SnowSparkleShader`, `RiverFlowShader`, `TreeMorphShader` — nine `*_shader.gd`
   wrappers in `src/rendering/` before this doc, all following one convention).
   Spells were the one combat-facing system that never joined it.
2. **The illustrated art this system was designed around was never wired
   in.** `docs/art/ai_sprite_prompts.md` section 8 has had complete,
   ready-to-run prompts for all 25 atoms — grouped into the same six
   silhouette families the procedural generator already uses — since
   2026-08-28. Nothing ever called the loader on them at the time this doc
   was first written. Every cast a player saw then was
   `ProceduralSpellEffectSprite`'s generated shape, the documented
   *fallback of last resort*
   ([illustrated_art_addressing.md](illustrated_art_addressing.md), design
   pillar 1), standing in because the bridge class that would prefer real art
   over it had not been written yet — the exact shape of gap
   `IllustratedItemArt`'s own doc comment named for items: *"the registry
   knew ~100 subjects... and not one pixel of the real art on disk ever
   reached the screen."* That bridge (`IllustratedSpellEffectSprite`, see
   "Mechanism" below) and the real art itself both landed 2026-09-24/26 —
   this doc's own shader layer, built the same day as the first version of
   the bridge, is what now plays on top of that real art.

## Design pillars

1. **Technique, never content.** A shader here may not change *what* an
   atom's silhouette is — only how it glows, warps space, or fades. The
   moment a shader starts drawing shapes (a spike, a ring, a cross) it has
   quietly become a second, undocumented art track competing with both the
   procedural generator and the illustrated sheets, and nothing here does
   that: every shader below either adds a halo *around* whatever sprite is
   showing or bends *what's behind* it — never the sprite's own pixels.
2. **Composable with either art track, unchanged.** A shader applies
   identically whether the sprite underneath it is procedural (true today,
   for all 25 atoms) or illustrated (true the moment real art lands, one atom
   at a time, per pillar 4 below). Swapping the sprite must never mean
   touching the shader, and vice versa — the same independence
   `pixel_art_engine.md` already established between "a generator says this
   is a leaf" and "the engine says how light falls on it."
3. **Deterministic, tuned math, CPU-mirrored.** No `RandomNumberGenerator`.
   Every shader's tuned curve exists first as a plain, tested GDScript
   function — a fragment shader cannot be asserted headless, so the same
   relationship `TorchGlow`/`WaterShader`/`SnowSparkleShader` already have to
   their own shaders holds here: the GLSL is a restatement of the pinned
   math, never an untested second copy of it (CLAUDE.md: tuned values must be
   test-pinned, never an eyeballed comment).
4. **Illustrated art is real art, and the bridge falls back safely.**
   Per [illustrated_art_addressing.md](illustrated_art_addressing.md) pillar
   1, procedural generation is the *fallback of last resort*, never the
   look. `IllustratedSpellEffectSprite` (below) is that bridge: illustrated
   when a family sheet covers the atom (true for all 25 today), procedural
   for one that doesn't yet — so a future atom added to the catalog before
   its own art exists behaves exactly as every atom did before this file
   existed.
5. **Category-driven, not atom-bespoke.** A shader technique is gated by the
   *shape family* the procedural generator and the sprite-prompt doc already
   agree on (burst/ring/cross/spiral/chevron/cloud — six families covering
   all 25 atoms), never by a per-atom special case. A new atom added to an
   existing family inherits its shader behaviour for free, the same "6 base
   sessions instead of 25 unrelated ones" efficiency `ai_sprite_prompts.md`
   already banks on for the art itself.

## Real-world grounding

A real discharge of energy disturbs more than the point it strikes: heat
visibly bends the air above it (schlieren/heat-shimmer), and a bright flash
casts light on everything nearby, not just the thing burning. Two real,
distinct optical phenomena, not one blurred effect — which is why this ships
as two separate shaders rather than one that tries to do both:

- **Light spilling onto the scene** → the glow halo, every atom, additive.
- **Space visibly bending near the release of the atom's own energy** → the
  impact distortion, gated to atoms whose effect *is* a sudden release
  (`fire_damage`, `frost_damage`, `shock_damage`, `ignite`,
  `induce_mutation`, `illuminate`, `fear` — the burst family; see
  `ai_sprite_prompts.md` §8a, which independently arrived at the identical
  seven-atom list from the *art* side).

## Mechanism

### `SpellGlowShader` — an additive halo, every atom

A `MeshInstance2D` sibling of the effect sprite (not a material on it —
mirrors `TorchGlow`'s own established shape: a dedicated quad, lazily built,
positioned each frame, `canvas_item` / `blend_add`), coloured by
`ProceduralSpellEffectSprite.color_for(atom_id)` — the *one* per-atom colour
table in the engine, read rather than re-declared, so a shader's halo and a
procedural sprite's own colour can never drift apart.

Driven by a single `progress` uniform (`0.0` at cast start, `1.0` when the
marker's own animation ends), so it is exactly in lockstep with the sprite's
existing grow/hold/fade beat rather than running a second, independently-timed
clock. The three beat fractions the uniform is measured against
(`grow_fraction`, `hold_fraction`) are *derived* from
`SpellEffectMarker.GROW_DURATION`/`HOLD_DURATION`/`FADE_DURATION` at the call
site, never restated as a second set of numbers — if the marker's timing is
ever retuned, the halo retunes with it for free.

`HALO_SIZE_MULTIPLIER` sizes the quad larger than the sprite's own
`ProceduralSpellEffectSprite.SIZE` — a halo that exactly matches the sprite's
silhouette reads as a coloured outline, not light spilling outward.

### `SpellImpactDistortionShader` — screen warp, burst family only

A `ShaderMaterial` on the effect sprite itself (this one legitimately needs
to sample what's *behind* the sprite, so it belongs on the node occupying
that screen position) using `hint_screen_texture` to offset the sampled
`SCREEN_UV` radially outward from the effect's own centre by a magnitude that
peaks early in the beat (the instant of release) and decays both with
distance from centre and with elapsed progress.

Gated by `SpellImpactDistortionShader.atom_gets_distortion(atom_id)`, which
reads `ProceduralSpellEffectSprite.shape_for(atom_id) == "burst"` — never a
second, independent atom list. A slow ring settling into place or a cloud
drifting onto a target should not visibly warp the world around it; a
fireball or a shock bolt releasing should.

**A real, shipped bug, found by a live report and fixed 2026-10-02:
"spells show no improvement in rendering and now render a visible square
which looks broken."** The fragment function wrote `COLOR = texture(
screen_texture, SCREEN_UV + offset)` and never read the sprite's own
`TEXTURE`/`COLOR` at all. A canvas_item fragment function that never
samples its own texture owns the whole pixel and draws nothing of the
sprite it is attached to — every burst-family cast (`fire_damage`,
`shock_damage` among them — Fire Bolt and Spark, the mage's own two
starting attacks) painted an opaque, barely-warped copy of the background
across the effect sprite's entire rectangular quad, full stop, with no
burst shape and no transparency surviving in it. Confirmed photographically
before fixing (`tools/probe_spell_distortion_render.gd`, a real-GPU render
via `xvfb-run ... --rendering-driver opengl3`): the burst shape was
completely invisible, replaced edge to edge by the checkerboard test
background. Fixed by capturing `COLOR` (already `texture(TEXTURE, UV) *
modulate`, the canvas_item default — this codebase's own established
convention, see `wind_sway.gd`/`tree_morph_shader.gd`'s matching doc
comments) before overwriting it, then compositing —
`mix(warped_background, original_color, original_color.a)`, forced fully
opaque on output since the shader already manually re-composites the real
background itself. Re-rendered after the fix: the burst shows correctly,
the checkerboard around it is intact (barely perturbed by the warp, as
designed). The gap this slipped through: every existing test either
checked the CPU-mirrored math or string-matched keywords in the GLSL
source — nothing checked that the shader preserves its own sprite's
content, and a fragment shader cannot be rendered headless, so the defect
was invisible to every automated check until someone actually looked at a
live cast. `test_shader_captures_its_own_color_before_overwriting_it`
closes that gap for this shader; `SpellGlowShader` was checked against the
same failure mode and does not have it — it never discards an underlying
sprite in the first place, since its `MeshInstance2D` halo draws pure
procedural colour with nothing beneath it to preserve.

### `IllustratedSpellEffectSprite` — the bridge that shipped

Not `IllustratedItemArt`'s per-subject registry/resolver/loader lattice —
this doc's own first draft specified that shape, but delivery (below)
changed the packaging enough that a simpler, purpose-built loader fit
better than bending the general five-axis address onto it. `has_look(atom_id)`
/ `frames_for(atom_id)` is the whole contract `SpellEffectMarker` needs:
illustrated frames when the atom's family sheet covers it (true for all 25
today), an empty array — the fallback-to-procedural signal — for one that
doesn't.

**Delivered as one sheet per shared shape family, not one per atom.**
`ai_sprite_prompts.md` §8's prompts are per-atom, but generation batched by
the procedural generator's own six silhouette families instead —
`assets/sprites/magic/{fire,ring,cross,chevron,cloud}.png` (`cross.png`
holds two: cross rows 0–2, spiral rows 3–5) — each atom still its own
distinct 6-frame row within its family's sheet
(`_FAMILIES[family_key].row_bands[i]`). A delivery-efficiency divergence
from the address table this section originally specified, not a design
one: every atom still reads as its own distinct picture, and the address
below is now family + row rather than one file per subject.

Frames are baked at `CANVAS_SIZE` (128px, real source detail — the earlier,
smaller canvas this doc originally specified measured as destroying exactly
the detail that reads as fire vs. lightning vs. ice) and centred on that
canvas; `SpellEffectMarker` compensates the on-screen size
(`DISPLAY_WORLD_SIZE`) so switching between an illustrated atom and the
smaller procedural fallback never visibly jumps in size.

### The real 6-frame beat plays back

`ai_sprite_prompts.md` §8 specifies a real 6-frame wind-up/peak/fade row per
atom, and `SpellEffectMarker.play` now steps through all of them (a second,
parallel `Tween`, evenly spaced across the marker's own
`GROW_DURATION+HOLD_DURATION+FADE_DURATION` beat) rather than tweening one
static frame — the increment this doc's first draft named as the natural
next step, honestly left unbuilt because nothing could exercise real
frame-timing before real art existed to play back. It now can, and does.

## Status

- ✅ **The glow halo is real and tested** (2026-09-24) — `SpellGlowShader`,
  additive, per-atom colour, timed off the marker's own beat.
  `test_spell_glow_shader.gd`.
- ✅ **The impact distortion is real and tested** (2026-09-24, a real
  content-discarding bug fixed 2026-10-02 — see "Mechanism" above) —
  `SpellImpactDistortionShader`, gated to the seven burst-family atoms,
  screen-space radial warp, composited with the sprite's own art rather
  than replacing it. `test_spell_impact_distortion_shader.gd`, verified
  photographically via `tools/probe_spell_distortion_render.gd`.
- ✅ **Real illustrated art exists for every atom, and both shaders play on
  top of it** (2026-09-24/26) — `IllustratedSpellEffectSprite` (family-sheet
  delivery, see "Mechanism" above), `SpellEffectMarker.play()` wired to draw
  it and layer both shaders over whichever art is showing.
  `test_illustrated_spell_effect_sprite.gd`, `test_spell_effect_marker.gd`.
- ✅ **The real 6-frame beat plays back.** See "The real 6-frame beat plays
  back" above.
- ⬜ **No shader exists for the other five silhouette families** (ring,
  cross, spiral, chevron, cloud). Named rather than silently narrower than
  "magic effects" sounds: this pass ships the two techniques the *burst*
  family and universal light-spill call for, grounded in a real optical
  distinction (§"Real-world grounding" above), not a first slice of five
  more to come unannounced. A ring settling into place (freeze/root/shield)
  or a slow spiral (slow/gravity_shift) plausibly wants its own techniques
  — a rime-frost edge, a gentle lens warp — each deserving the same
  real-world grounding and CPU-mirror rigor as the two here, not a
  copy-pasted distortion with different numbers.
