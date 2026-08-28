## Spell runtime: from a parsed AST to an actual effect

[magic.md](magic.md) specifies the DSL and its cost model; three pure modules
already implement pieces of it (`spell_parser.gd`, `spell_atom_catalog.gd`,
`spell_cost.gd`). Nothing turns a parsed spell into an actual game effect —
this doc specs the executor that closes that gap, scoped to **a player
casting a spell they already know**. Enchantments (`on hit`) and NPC
instructions (`on <behavior-trigger>`) are the DSL's other two surface forms
(magic.md's "unifying model") and reuse the same executor in principle, but
wiring either of *those* triggers in is explicitly out of scope here.

### A new resource: mana

`class_archetype.gd` has always defined a `max_mana` bonus per class (mage
+50, warrior 0, ...), and `spell_parser.gd`'s own canonical example guards on
`wielder.mana >= @cost` — but `Player.apply_class`/`_apply_skill_stat` never
read that key, so mana has never existed as a live stat. It cannot reuse
**stamina**: `docs/concept/survival.md`'s "Stamina scope" section is explicit
and deliberate that stamina is traversal-only and **combat stays off it by
design** ("kept deliberately separate so the two systems don't fight each
other for the same tension"). Casting a damage spell is combat. Mana is a
new, separate resource:

- `Player.max_mana`/`mana`, set in `apply_class` the same way `max_health`
  is: `max_mana = maxf(0.0, float(stats.get("max_mana", 0.0)))` (no base
  floor the way health has one — 0 mana is a valid, meaningful state for a
  warrior, not a broken one). `mana = max_mana` on class-apply.
- Regenerates passively at a flat per-second rate while not dead (mirroring
  `SurvivalMeters`'s own bespoke-field-plus-rate-constant shape, not a new
  shared `Meter` base class — no such base class exists anywhere in this
  codebase to extend; every meter here is copy-pasted, not inherited).
- Spent atomically on a successful cast, refused (no state change) on an
  unaffordable one — mirrors `Wallet.spend`'s own "never mutated on failed
  spends" contract exactly.

### Delivery method rides the parser's existing `event_arg` slot

Magic.md says a spell is "atoms plus a delivery method" (self/touch/
projectile/area), and `spell_cost.gd` already prices all four
(`_DELIVERY_MULT`) — but `spell_parser.gd`'s grammar has no delivery field
anywhere. It doesn't need one added: `on EVENT(ARG):` already accepts a
parenthesized ident, currently unused by anything. `on cast(touch): ...`
already parses today, with `event_arg == "touch"`. The runtime reads
`event_arg` as the delivery method for a `cast` rule, defaulting to
`"touch"` when omitted. No parser change.

### Targeting: a new pure module, not melee's AOE

`MeleeAttack.targets_in_range` is a radius-only AOE sweep (everything in
range, regardless of facing) — right for a sword swing, wrong for a directed
spell. Nothing in this codebase resolves "the nearest thing in front of me,
out to some range" (`TileTargeting.facing_tile` is the closest analog, but
it resolves one fixed adjacent *tile*, not an entity search with a range).
New: `src/gameplay/spell_targeting.gd`, mirroring `melee_attack.gd`'s pure,
index-based shape —

- `self`: the caster.
- `touch`: nearest creature/player within a short fixed range, no facing
  cone (matches "touch" meaning point-blank contact, not aim).
- `projectile`: nearest creature/player within a longer range **and** within
  a facing cone (a dot-product/angle check against `_last_facing_direction`)
  — approximates a directed shot without building real projectile flight
  (see Open questions).
- `area`: every creature/player within a radius of a point in front of the
  caster (structurally `MeleeAttack.targets_in_range` reused at a resolved
  point, not the caster's own position).

No delivery method gets real travel-time/flight animation — see
item_illustrations.md's own already-recorded gap ("no ranged projectile
flight visual exists anywhere") and magic.md's atom-effects section, which
defers this identically. `projectile`/`area` resolve instantly at cast time,
exactly like every other instant-AOE in this game (`_perform_attack`'s own
sweep fires immediately, cosmetic swing aside).

### Trigger: a new input action, not the hotbar

`HotbarAction._ACTION_BY_KIND` decides EQUIP/USE/PLACE purely from an
*item's* kind — a spell isn't an inventory item (nothing to equip, consume,
or place), so it doesn't fit and doesn't try to. Casting gets its own
keybinding (`Keybindings.ACTIONS`, a new `"cast"` entry — every entry today
is already in active use, so this is a genuinely new slot, not a repurposed
one) and its own `_cast_step(delta)` in `Player`, structurally identical to
`_attack_step`: momentary-input latch, rising edge, its own cooldown (see
below), `play_attack_swing`-style visual, then resolve.

### Cast resolution order

1. Look up the rule with `event == "cast"` in the spell's parsed AST
   (`kind == "spell"` blocks only — enchant/instruct stay out of scope).
2. Compute `cost := SpellCost.paid_mana(pipeline_atoms, delivery,
   governing_stat)` and `cast_time := SpellCost.cast_time(...)`.
   `governing_stat`/`haste_stat` default to `0.0` — `evocation`/`focus`
   skill-web nodes exist by name (skills.md's Mage row) but nothing computes
   a live "spell power"/"haste" stat from them yet; wiring that is a
   follow-up, not blocking a working runtime (0.0 is baseline efficiency,
   not broken efficiency).
3. **Affordability is unconditional**, not opt-in via a written guard —
   Constraint layer 1's whole point is that cost can never be skipped.
   Refuse (no mana spent, no atoms run) if `caster.mana < cost`, and set the
   same one-shot result-message-plus-timer UX every other Player feedback
   already uses (`trade_message`'s exact triple: `_cast_result_message`/
   `_cast_result_timer`/public `cast_message`, wired into `World`'s existing
   shared message-stack) — `"Not enough mana."`, mirroring
   `_attempt_a_purchase`'s `"Not enough gold."` precedent exactly.
4. If the rule *also* has an explicit `when` guard (e.g. the canonical
   `wielder.mana >= @cost`), evaluate it too via a small guard evaluator —
   dotted-path lookup against a caster-context Dictionary the runtime builds
   from live Player stats (`{"wielder": {"mana": ..., "health": ...}}`),
   `@cost` resolving to the value computed in step 2, six comparison ops.
   Refuse identically on failure. This makes an explicit guard an *extra*
   condition an author can add, never a way to skip the baseline check.
5. Spend `cost` from `mana`.
6. Resolve the target(s) via `spell_targeting.gd` per the rule's delivery.
7. Run the pipeline: each atom step applies its real effect (see table
   below) against the resolved target, in order.
8. Play the visual: existing `play_attack_swing`-style gesture (deferred
   per-item cast art — see item_illustrations.md's own deferred swing-art
   note, same reasoning) plus a new procedural effect sprite per atom (see
   below), at the target.

### Per-atom mechanics

`spell_atom_catalog.gd`'s own `mag_ref`/`dur_ref` shape is the organizing
axis — not the `category` field, which only drives the *visual* palette
(magic.md's atom-effects section). Three real mechanical shapes:

| Shape | Atoms | Mechanic |
|---|---|---|
| **Instant, magnitude** | `fire_damage`, `frost_damage`, `shock_damage`, `poison_damage` | `target.take_damage(magnitude)` — duck-typed, already shared by Player and CreatureMarker, already mitigation-aware (armor/block on Player, boss-aggro gate on creatures). All four are mechanically identical for now — no elemental-interaction/resistance model exists yet (magic.md's own open question); they differ only in visual color. |
| | `minor_heal`, `major_heal` | Restore `health`/`info.health` toward `max_health`/`info.max_health`, clamped. |
| | `push`, `pull` | `MeleeAttack.knockback_vector`-shaped math (away from / toward the caster) → `CreatureMarker.apply_knockback`. Player currently has **no** `apply_knockback` sink (nothing in this game has ever knocked the player back) — add a minimal, symmetric one so a hostile-cast push/pull isn't creature-only. |
| | `teleport` | `target.position = target.position + facing_direction * magnitude` (pixels). No dry-land validation (that's `_compute_dry_land_spawn_tile`-grade expensive, chunk-aware work, wrong cost for an instant cast) — an honest, documented gap, not a silent one. |
| | `accelerate_growth` | Targets whatever `FarmPlot` sits at the caster's faced tile (`TileTargeting.facing_tile`, the same single-adjacent-tile resolution `build`/`destroy` already use) and calls its real `advance(magnitude)` — the exact hook `FarmPlot`'s own per-tick simulation already uses, just with a bigger delta. No-op (mana still spent) if nothing is there — "even an affordable spell still has to land" (magic.md, Constraint layer 2). |
| **Timed, no magnitude** | `ignite`, `blight` | A new `IgniteModel`, mirroring `VenomModel` exactly (`damage_per_second(stacks)`), tracked via the existing `DebuffStack` and ticked by a new `_ignite_step`/`_blight_step` mirroring `Player._venom_step` line for line — including a CreatureMarker-side equivalent, since `DebuffStack` itself is target-agnostic even though its only current consumer (venom) is Player-only. |
| | `freeze`, `root` | A `DebuffStack`-tracked "rooted" status; `_authority_step` zeroes `input_direction` while active (Player), and the creature-movement step skips its own movement resolution while active (CreatureMarker) — `freeze`/`root` are mechanically identical (both "can't move for duration"); they stay distinct atoms because their cost/tier differ and their visuals will. |
| | `slow` | A `DebuffStack`-tracked multiplier folded into `Player.current_speed_multiplier`'s existing product chain as one more term, and into whatever the creature-side movement-speed equivalent is. |
| | `suppress_mutation` | Tracked via `DebuffStack` as a real, queryable status; not yet consulted by anything (mutation induction itself is Tier 2 below) — honestly inert until that lands, not faked. |
| | `illuminate` | A local light radius flag for duration — cosmetic-only for now (no light-rendering system exists to attach to yet beyond the existing day/night tint); tracked via `DebuffStack` so it's real, queryable state even before a renderer consumes it. |
| | `calm`, `fear` | `CreatureBehavior.decide(context)` is a **pure function of a context Dictionary** the caller builds (includes `"temperament"`) — not a hardcoded read of the creature's own permanent `CreatureInfo.temperament`. `fear`/`calm` don't touch `creature_behavior.gd` at all: `CreatureMarker` overrides the context's `"temperament"` value for the debuff's duration before calling `decide()` (forcing a `flee` read for `fear`, a passive one for `calm`) — additive at the call site, zero changes to the pure decision function itself. |
| | `reveal` | `EarthChunkManager.mark_chunk_explored(chunk_coord)` for every chunk within radius of the target point — the real, live `ExploredTiles` wrapper, whose own doc comment already flags it as session-only/unpersisted (an existing, named gap this doesn't need to fix). Currently has exactly one caller (`/map`); this becomes the second. Marking is permanent (`ExploredTiles` has no unmark), so `dur_ref` reads here as "how far a reveal-pulse radius reaches," not "how long before it's forgotten." |
| | `summon_wisp` | Tracked via the same generic `DebuffStack` status dispatch as every other timed atom (`SpellStatusEffects.SUMMON_WISP`) — simpler than an actual companion node, and deliberately **not** `BondedCompanionMarker` reused directly, since that class is permanent, capped, and save-persisted (`Player.bonded_companions`); entangling a timed summon with that already-shipped system risks its persistence contract for no benefit. Real, queryable state today; no visual companion node or combat behavior yet (a further-simplified scope than a first pass at this doc proposed — named here rather than silently shipped as something it isn't). |
| **Timed, with magnitude** | `shield` | A simple bespoke `_shield_absorb_remaining`/`_shield_time_remaining` pair on Player (mirrors `Block`'s own "bespoke field, not a generic system" precedent), consumed inside `take_damage` before armor mitigation, expiring at zero or at `duration`, whichever first. |
| | `gravity_shift` | No vertical/airborne axis exists anywhere in this 2D top-down game (confirmed: zero z-height state on any entity) — approximated as a **single strong shove** scaled by both magnitude and duration (a bigger `push`, via the same `apply_knockback` sink), not a sustained force or true gravity mechanic. Simpler than a continuous per-tick reapplication (which would need its own tracked timer state for one atom alone) while staying equally honest about being an approximation. |
| **Deferred entirely** | `portal`, `induce_mutation` | **Portal**: a two-endpoint linked-teleport needs infrastructure (a placed, discoverable, two-way link) this pass doesn't build — costs mana, plays its visual, has no mechanical effect yet. **Induce_mutation**: `TreeGenome.mutate()` is real and live (`tree_spread.gd`'s own natural-spread path), but only ever produces a *new child genome* for a *proposed sapling* — `chunk.gd`'s `planted_trees` has no supported single-entry genome overwrite, and forcing one risks corrupting save data for a cosmetic spell effect. Deferred rather than risked. |

That's 21 of 25 atoms with a real mechanical effect (four honestly simplified
— teleport's placement, gravity_shift's force-not-gravity, summon_wisp's
no-combat, reveal's permanence — and clearly labeled as such), 2 fully
deferred (portal, induce_mutation), `suppress_mutation` tracked-but-inert
pending induce_mutation.

### A fixed example spellbook, not a spell-authoring UI

There is no spell-editor UI, no "known spells" list on Player, and no
skill-tree atom-unlock gate yet (skills.md's own status section: "no
atom-unlock/parameter-cap hook into magic.md's catalog... this doc has
always called for" — a separate, real gap this doesn't close). Exactly like
`ItemCatalog._ITEMS`/`CraftingRecipeBook` before any crafting UI existed,
this pass ships a small fixed table of pre-authored example spell texts
(parsed once, cached), directly castable — e.g.:

```
spell "Fire Bolt" {
    on cast(touch) when wielder.mana >= @cost:
        fire_damage(magnitude: 8)
}
```

Skill-gating which atoms a player may use stays exactly as unbuilt as it was
before this doc — every fixed example spell is castable by anyone with
enough mana, the same "authoring/access depth is a later layer" scoping
`ItemCatalog` itself already established for crafting.

### Procedural effect visuals

Per [magic.md](magic.md#atom-effects-render-as-composite-spritemaps-one-per-atom-2026-08-28),
effects are keyed by atom id, not spell id, and get a procedural-first
fallback before any illustrated sheet exists — the same two-track pattern
`ProceduralItemSprite` already established for items. A new
`ProceduralSpellEffectSprite` (`src/rendering/`) generates one small image
per atom id from a `{color, shape}` table (mirroring `_ITEM_LOOKS`'s exact
shape), reusing a handful of shared primitives (burst, ring, spiral, cross,
drip, chevron) across the 25 atoms rather than 25 bespoke draw routines —
the same "shapes are reused across many entries" convention
`ProceduralItemSprite` already follows for its own ~80 items. Motion is a
procedural Tween (grow → hold → fade), not a hand-baked multi-frame
animation, spawned by a small new `SpellEffectMarker` node at the resolved
target and freed on completion — thin, untested Node-composition glue over
tested pure generation, matching this codebase's established boundary.

### Open questions

- No real projectile flight exists for `projectile`/`area` delivery (nor
  for anything else in the engine) — instant-resolve-in-a-cone is a
  deliberate stand-in, not a final design.
- `governing_stat`/`haste_stat` default to 0.0 — wiring real
  `evocation`/`focus` skill-web contributions is a named follow-up.
- Elemental interactions (fire+frost→steam, per magic.md's own open
  question) are not modeled; the four damage atoms are mechanically
  identical today.
- `calm`/`fear`'s context-override approach only takes effect the next time
  `CreatureBehavior.decide()` runs for that creature — no guarantee of
  interrupting an action already in progress that tick.
- Whether `suppress_mutation`/`illuminate` ever get a real consumer depends
  on `induce_mutation` and a lighting system respectively, neither of which
  this pass builds.
- `SpellCost.cast_time` is computed (`SpellExecutor.cast_time_for`) but not
  yet enforced as an actual pre-cast delay or interrupt window — casting
  today resolves instantly on the rising input edge, gated only by mana and
  the physical key-press itself (no artificial cooldown, unlike melee's
  `ATTACK_COOLDOWN` — mana affordability already throttles repeat casts, and
  melee has no "ammo" cost to do the same job).
- No spell-selection UI exists yet, so the "cast" key always casts
  `Player.DEFAULT_CAST_SPELL_ID` ("fire_bolt") — `cast_spell(spell_id)`
  itself already accepts any known id; only the "which spell" binding is a
  placeholder.
