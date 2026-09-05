# Capture DSL: generic animal-capture mechanics

Reported directly: an experienced crafter should be able to invent completely
new capture items — "every animal needs to be catchable with the right
device" — the same way [magic.md](magic.md) lets a crafter invent new spells,
and the physics of a specific device (e.g. "a butterfly gets caught with a
probability upon performing its catch action") should be authored as data,
not hand-coded per tool.

[taming.md](taming.md)'s "Any animal, the right tool" section already made
*which* device a species needs fully generic (read off `AnimalAnatomy`
body-plan data, not a species allow-list). What stayed hand-coded was *what
happens* when the device is actually used: the lasso's restrain-and-struggle
loop and the net's instant, always-succeeds catch are both bespoke Player/
CreatureMarker code, not data a new device could reuse or vary. This doc
specs the DSL that closes that second gap, in the same spirit
[spell_runtime.md](spell_runtime.md) closes it for magic: a small text
language, parsed into a plain AST, executed by a small set of pure modules.

## Design pillars

- **The tool-fit layer stays exactly as it is.** `CaptureTool.required_tool_for`
  deriving lasso/snare/net/trap/reinforced-rope from body-plan data is
  already the generic, derive-don't-enumerate mechanism this whole family of
  docs insists on. This DSL does not re-decide *which* device a species
  needs — it specs what a device *does* once it's the right one in hand.
- **Odds are derived from device tuning plus real target biology, never
  eyeballed per throw.** A device's DSL text supplies one tuned `base`
  number; everything else the odds depend on (an individual's boldness,
  say) is real data the simulation already tracks, the same "derive, don't
  author a special case" discipline `magic.md`'s cost model holds itself to.
- **A pipeline can fail partway, on purpose.** Magic's pipeline is an
  unconditional sequence — every atom happens. Capture's is not: a `catch_roll`
  atom can fail and short-circuits everything after it in the same pipeline.
  This is capture's own constraint layer, as load-bearing here as "cost is
  derived" is to magic: an author cannot write a device that always works,
  because the roll atom is what stands between "attempted" and "happened."
- **One tool holds at most one thing, and holding it is a real state, not an
  instant transaction.** Netting a monarch does not instantly decide its
  fate the way it does today — the net becomes loaded, and the player
  decides what happens to what's inside it. A loaded tool cannot catch again
  until it's empty, the same real constraint a one-net-in-hand trapper has.

## Real-world grounding

- A netting attempt against a real insect is genuinely probabilistic and
  genuinely biology-linked: a habituated or sluggish individual sits still
  long enough to be netted; a wary one is airborne before the hoop closes.
  `FlyerPersonality.boldness_of` already models exactly this axis (it exists
  specifically so netting bold individuals out of a meadow makes the meadow
  shyer over generations) — this DSL is the first thing that actually reads
  it at catch time, rather than only at flee/dance time.
- A field net (or trap, or bottle) is a real, single container: you cannot
  scoop up a second insect while the first is still inside without dealing
  with it first. "The net is full, decide what happens to what's in it
  before it can catch again" is not a game rule bolted on for balance, it's
  what a net physically is.

## Grammar

One block kind, `capture`, structurally identical to
[magic.md](magic.md)'s `on EVENT(ARG) when GUARD: pipeline` shape (same
tokenizer, same `|>` pipeline operator, same `>= <= > < == !=` guard
operators, same number / `@ref` / dotted-path operand grammar) — parsed by
its own small recursive-descent parser (`capture_parser.gd`), not a shared
one, the same way `npc_instruction_parser.gd` is already a structural sibling
of `spell_parser.gd` rather than a subclass of it. Purely structural, like
the magic parser: an unknown atom parses fine, and is rejected (or simply
never dispatched) one layer up.

```
capture "Butterfly Net" {
  on catch when target.tier == "flyer":
    catch_roll(base: 0.65) |> hold_captive()
  on release:
    release_captive()
  on transfer(glass_bottle):
    move_captive()
}
```

`on catch`'s guard is what lets multiple devices for different tiers coexist
safely under one grammar as more get authored — a snare's block would guard
`target.tier == "legless"`, and the wrong device against the wrong tier
guards itself out rather than needing a lookup table anywhere else.
`on transfer(glass_bottle)` reuses the event-argument slot to name *which*
container a rule handles, the same reuse trick `on cast(touch)` already
makes of that slot for delivery method.

## Atom catalog (v1)

A small, fully-wired set — unlike magic's catalog, every atom below has a
real dispatcher and a real caller; nothing is catalogued ahead of having
somewhere to run.

| Atom | Category | What it does |
|---|---|---|
| `catch_roll(base)` | roll | The only atom that can fail. Resolves pass/fail from `CapturePhysics.catch_chance(base, boldness)` against a caller-supplied roll; failure stops the rest of the pipeline. |
| `hold_captive()` | effect | Sets the tool `Item`'s `captive_species` to whatever was being caught. |
| `release_captive()` | effect | Clears `captive_species` back to empty. |
| `move_captive()` | effect | Reads `captive_species` off the tool and reports which existing curiosity item results (reusing the current `jarred_insect`/`caged_songbird` split), for the caller to actually grant and to clear the tool. |

## Physics: how a chance is derived

`capture_physics.gd`, pure and property-tested like `spell_cost.gd`:

```
catch_chance(base, boldness = FlyerPersonality.MIDDLING_BOLDNESS) =
    clampf(base + (boldness - 0.5) * BOLDNESS_WEIGHT, 0.0, 1.0)
```

`BOLDNESS_WEIGHT := 0.3` (tested, not eyeballed): a middling-boldness
individual (0.5, the default for anything with no personality rolled — a
hand-placed test fixture, say) gets exactly the device's own `base`; the
boldest real individual (1.0) gets `base + 0.15`; the shyest (0.0) gets
`base - 0.15`. With `butterfly_net`'s own `base := 0.65`, real odds land in
`[0.5, 0.8]` — nudged by the individual, never turned into a coin flip or a
certainty by it alone.

## Resolution order

Mirrors [spell_runtime.md](spell_runtime.md)'s own resolution-order section:

1. `CaptureExecutor.capture_rule(ast)` finds the device's `on catch` rule.
2. Its guard is evaluated against a small context Player builds at the
   throw site (today: `{"target": {"tier": "flyer"}}`). A tier mismatch
   means nothing happens — the same "wrong tool, no new failure state, just
   nothing" precedent `taming.md` already set for the lasso.
3. `resolve_catch(rule, context, roll)` walks the pipeline. The roll itself
   is supplied by the caller, not generated inside the executor — the same
   split `CreatureMarker._step_restraint`'s own
   `hash("%d_%d_struggle" % [wander_seed, count])` roll already keeps
   between "pure decision given a roll" and "where the roll comes from."
   Player salts its roll with an incrementing attempt counter, not the
   flyer's bare `wander_seed` alone — a bare-seed roll would make every
   retry against the same still-alive flyer land on the identical outcome
   forever, silently making one miss unwinnable.
4. On success, `hold_captive` sets the tool's `captive_species`; Player
   removes the target from the world. On failure, nothing changes — the
   flyer's own existing `FlyerPersonality` flee/dance reaction keeps running
   exactly as it already does, untouched by any of this.
5. `on release`: no guard, no roll — clears `captive_species`. Does **not**
   respawn a live creature back into the world (⬜, an honest, named gap —
   see Open questions).
6. `on transfer(CONTAINER)`: matched by `event_arg == CONTAINER`.
   `move_captive` reports the resulting curiosity item id; Player consumes
   one `CONTAINER` from inventory and grants it.

## Integration with input & items

- Catch/Release reuse the **existing dedicated capture-tool key**
  (`Player.perform_rope_verb` → `_throw_capture_tool` → `_throw_net`), not
  the hover-based `primary_action`/`secondary_action` verb scorer
  (`AnimalActions`) — because that scorer's target lookup
  (`Player._action_target`) only ever scans `CreatureMarker.GROUP_NAME` or an
  already-lassoed animal, and has never been able to see an ambient flyer at
  all. `_throw_capture_tool` already branches net-vs-rope-tool by tool id;
  it grows one more branch: a loaded net releases instead of throwing.
- "Put into bottle" has no hover target at all — it depends only on what's
  in the player's hand and their bag. Rather than bending `AnimalActions`
  (built entirely around a live animal's `animal_state()`), it's a small new
  sibling pure scorer, `capture_item_actions.gd`, consulted by
  `_action_slots_step()` only when the existing hover-verb path offers
  nothing for that slot — so Feed/Ride/Order/Release are provably unchanged.
- `Item.captive_species` is one instance field, added the same deliberate
  way `Item.wear` already is: state that starts blank and accumulates over
  one specific item's lifetime, a documented exception to "Item is a shared,
  immutable definition."

## Status / mechanisms

- ⬜ `capture_parser.gd` / `capture_atom_catalog.gd` / `capture_physics.gd` /
  `capture_executor.gd` / `capture_atom_effects.gd` / `capture_book.gd`
- ⬜ `Item.captive_species`; `glass_bottle` catalog + icon entry
- ⬜ `capture_item_actions.gd` (the "Put into bottle" scorer)
- ⬜ Player wiring: probabilistic `_throw_net`, `_release_net`,
  bottle-transfer, updated tests
- ⬜ `bottled_creature_wander.gd` (confined fly/rest state)
- ⬜ `illustrated_glass_bottle_sprite.gd` (the fixed 3×2 sheet reader)
- ⬜ `bottled_creature_view.gd` and its `DroppedItem` wiring
- ⬜ **The restrain-and-struggle tier (lasso/snare/trap/reinforced rope) is
  not expressed in this DSL.** It stays on `taming.gd`'s existing
  `break_free_chance`/`hold_chance` model, which is live, tested, and
  playable end to end — porting it into `capture` text (a `struggle_roll`
  atom delegating to those same functions) is real future work, not
  attempted here, mirroring exactly how `magic.md` itself leaves `enchant`/
  `instruct` unwired against its own executor in its first pass.

*(This section gets a pass once the corresponding code lands — see
`docs/progress.md` for the dated, narrative account of what actually
shipped.)*

## Rendering a bottled catch

A loaded `glass_bottle` is not a flat trophy — reported directly: the
bottle's own composite sheet has two rows, a background layer and a
foreground layer, and a bottled creature should render sandwiched between
them, alive: flying around, settling, flapping its wings.

`assets/sprites/items/glass_bottle.png` is a fixed 3×2 grid (measured:
1536×1024, six 512×512 cells) — three condition columns (pristine/worn/
broken, reusing [item_durability.md](item_durability.md)'s existing
`ItemWear.condition_for` vocabulary rather than inventing a second one) by
two rows: row 0 uncorked (the back layer — what sits behind whatever the
bottle holds), row 1 corked (the front layer — the near glass and its seal).
Both rows carry real, continuously-varying alpha through the glass body
(measured, not just at the silhouette edge) — this is a deliberately
painted "see-through" material, not a flat icon, which is exactly what
makes the sandwich read as looking *through* glass at something inside it
rather than a sticker glued on top of one. `composite_sheet_slicer.gd`'s
blob-detection is the wrong tool here — this grid is fixed and regular, not
irregularly laid out — so it's read the same "fixed-position, measured Y/X
bands" way `item_illustrations.md`'s wooden_club sheet already is.

**The creature layer reuses existing generators wholesale, not a new art
pipeline**: `ProceduralButterflySprite.generate_flap_textures`/
`generate_settled_textures` already produce exactly "flying" and "settled,
wings folded" frame sets, per species, and `WingbeatBounce.bounce_offset`
already derives the per-beat vertical bob from real wingbeat physics. None
of that is rebuilt. What a bottled creature needs that
`AmbientFlyerMarker`'s own animation state machine doesn't offer is far
simpler than what that machine models (no courtship, no nectaring, no
perched-bird logic — nothing in a sealed bottle forages or courts), so it
gets its own small state: `bottled_creature_wander.gd` alternates
deterministically between a short FLYING leg (drifting to a fresh point
inside the bottle's interior bounds) and a longer RESTING leg (settled at
that point), continuous across the transition, the same hash-seeded-not-RNG
discipline every other per-individual timing in this codebase already
holds to.

Only species `ProceduralButterflySprite` actually covers get a live
creature layer; a bottled bird (caught the same way, see taming.md's
"Netted" class covering both) falls back to the bottle alone rather than
inventing bird-in-a-bottle art nobody asked for — an honest, named
simplification, not an oversight.

**Where it renders**: the world-DROPPED item, not the inventory icon or
hand-held view. Every other surface in `item_illustrations.md`'s own states
table converges on one static texture per item on purpose (icon/ground/
in-hand all "reuse the icon") — animating an inventory slot would be a
first, unplanned departure from that. A dropped item is already a live
`Sprite2D`-based scene node (`dropped_item.gd`), the same kind of place this
codebase already puts a live diorama (`CharacterPreviewDiorama`), so a
loaded bottle set down in the world gets a small child view
(`bottled_creature_view.gd`: back sprite → creature sprite → front sprite)
instead of `DroppedItem`'s ordinary single flat texture.

## Open questions

- Should `release` actually respawn a live creature back into the world,
  rather than just emptying the tool? Symmetrical and arguably more honest
  physically, but not asked for and not built here.
- Does `struggle_roll` (the restrain tier) ever get ported into this same
  grammar, or do the two tiers stay permanently separate because they are
  genuinely different physical acts — an instant swing versus a multi-minute
  held contest? Left open rather than forced.
- A second instant-roll device for a different tier (a hand trap for a
  mouse-scale animal? a hook-and-line for a fish?) should already fit this
  same grammar and catalog unmodified, needing only a new `capture_book.gd`
  entry with the right guard — untried in practice, since only one device
  exists so far.
