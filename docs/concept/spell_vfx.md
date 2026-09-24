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
   2026-08-28. Nothing ever called the loader on them. Every cast a player
   has ever seen is `ProceduralSpellEffectSprite`'s generated shape, the
   documented *fallback of last resort*
   ([illustrated_art_addressing.md](illustrated_art_addressing.md), design
   pillar 1), standing in because the bridge class that would prefer real art
   over it was never written — the exact shape of gap
   `IllustratedItemArt`'s own doc comment named for items: *"the registry
   knew ~100 subjects... and not one pixel of the real art on disk ever
   reached the screen."*

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
   look. `IllustratedSpellEffectArt` (below) is the bridge that was missing:
   illustrated-if-present, procedural if not, exactly
   `IllustratedItemArt`'s proven two-track shape — so dropping in one atom's
   PNG at a time is never a code change, and a subject with no art behaves
   exactly as it did before this file existed.
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

### `IllustratedSpellEffectArt` — the missing bridge

Exactly `IllustratedItemArt`'s shape, re-keyed for atoms: registry entry →
resolver (against the real file tree) → loader (slice, chroma-key, anchor) →
`ImageTexture`, with `texture_for(atom_id)` the one call `SpellEffectMarker`
needs — illustrated when `assets/sprites/<atom_id>/effect/any/default/cast.png`
exists, `ProceduralSpellEffectSprite.texture_for(atom_id)` when it does not.

The address collapses three of the general convention's five axes to fixed
values, because none of them mean anything for a spell atom — no seasonal
variation, no durability/wear states, one drawn context — the same minimal
shape `illustrated_art_addressing.md`'s own precedent table already allows
(`IllustratedCropSprite`: "Separate files per part, states as frames
within"):

| axis | value | why |
|---|---|---|
| `subject` | the atom id | one per entry in `spell_atom_catalog.gd` |
| `context` | `"effect"` | the only way an atom is ever shown |
| `season` | `"any"` | a spell effect has no seasonal look |
| `state` | `"default"` | no durability/wear axis applies |
| `animation` | `"cast"` | the one wind-up/peak/fade row |

**Registered in the same shared `illustrated_art_registry.gd` every other
subject lives in** (`_SUBJECTS`), never a second bespoke registry — the doc's
own rule, "the registry never repeats [subject/context/season/state/
animation]; it holds only what the pixels cannot say."

### One frame, not yet the full beat

`ai_sprite_prompts.md` §8 specifies a real 6-frame wind-up/peak/fade row per
atom. `IllustratedSpellEffectArt.frames_for(atom_id)` returns all of them
when real art exists — but `SpellEffectMarker` still only asks for
`texture_for` (frame 0) and keeps animating it with its own `Tween`, exactly
as it does the procedural sprite today. Playing the real 6-frame row instead
of tweening one frame is the natural next increment, honestly left
**⬜ unbuilt** below rather than faked: nothing in this repo can meaningfully
exercise that frame-timing logic before real art exists to play back, and a
guess at it now would be untested motion pretending to be tested.

## Status

- ✅ **The glow halo is real and tested** (2026-09-24) — `SpellGlowShader`,
  additive, per-atom colour, timed off the marker's own beat.
  `test_spell_glow_shader.gd`.
- ✅ **The impact distortion is real and tested** (2026-09-24) —
  `SpellImpactDistortionShader`, gated to the seven burst-family atoms,
  screen-space radial warp. `test_spell_impact_distortion_shader.gd`.
- ✅ **The illustrated bridge exists and every atom is registered**
  (2026-09-24) — `IllustratedSpellEffectArt`, `texture_for` wired into
  `SpellEffectMarker.play()`. `test_illustrated_spell_effect_art.gd`.
- ⬜ **No atom has real illustrated art yet.** All 25 registrations resolve
  to the procedural fallback until a file exists at
  `assets/sprites/<atom_id>/effect/any/default/cast.png` — see
  `ai_sprite_prompts.md` §8 for the prompts, and its new addendum for what
  changed about them now that a glow shader exists.
- ⬜ **The real 6-frame beat is not played back.** `frames_for` returns it;
  `SpellEffectMarker` does not yet consume more than frame 0. See "One
  frame, not yet the full beat" above.
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
