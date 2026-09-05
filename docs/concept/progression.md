# Character Progression (XP, Levels, Skill Points)

The player-facing RPG shell that ties together the already-designed
[classes.md](classes.md) (archetype stat lenses) and [skills.md](skills.md)
(passive skill web). This doc specifies the connective tissue: how a character
is created (class pick), earns **experience**, gains **levels**, and spends the
**skill points** levels grant into the skill tree.

## Design pillars

1. **Class is a lens, not a cage** (per [classes.md](classes.md)). At character
   creation the player picks an archetype (warrior/mage/ranger/…) which applies a
   stat lens (`ClassArchetype.stats_for`) — a starting bias, freely respec-able
   later, not a permanent lock.
2. **Levels come from doing, not grinding a bar in a vacuum.** XP is earned from
   real play — defeating creatures now, later from crafting/foraging/quests — and
   each level grants a durable payoff (a small max-health bump) plus a **skill
   point** to spend in the passive web.
3. **Deterministic, testable curve.** The XP-per-level curve and skill-points
   schedule are pure, test-pinned functions (`ExperienceTrack`) — no eyeballed
   constants — so the bar and level always agree.

## Experience & levels

`ExperienceTrack` (stateful, pure logic) holds `total_xp`, `level`, and
`unspent_points`:

- **XP to next level** grows with level (a modest linear ramp), so early levels
  come quickly and later ones take longer — the standard RPG pacing.
- **Adding XP** rolls the level forward as thresholds are crossed and accrues one
  **skill point** per level gained; it returns how many levels were gained so the
  caller can react (heal to full, flash a level-up).
- **Bar readout**: `xp_into_level` / `xp_for_next_level` (and a `progress_fraction`
  in [0,1]) feed the HUD XP bar.

## Character creation & class

The **New Game** flow (main menu) lets the player pick a class before the world
spawns. The chosen archetype's stat lens is applied to the fresh player
(`ClassArchetype.stats_for` → base health/attack/mana/stamina offsets). Classes
are a starting bias; the skill tree is where a build actually diverges.

The same creator's **Starting Kit** tab is where the player picks their
starting gear — 3 items from a curated early-game pool, class-independent
(see [starting_kit.md](starting_kit.md) for the pool and why each item is or
isn't in it).

## Skill tree

Levels grant points; the **skill tree window** spends them on
`SkillTree`/`KeystonePassive` nodes (already-built pure logic), whose
`total_bonus(stat)` feeds back into the player's derived stats. Small stat nodes
gate keystones (a minimum-nodes-spent requirement), matching [skills.md](skills.md).

## Ecological literacy: XP from reading the world, not just fighting it

Closes the "XP from non-combat sources" gap below with a specific, grounded
mechanism rather than a generic "foraging gives XP" grind: **XP for
skillfully engaging the real simulation systems this game already runs**,
not for the raw act of foraging/farming itself.

- **Peak-timing rewards**, not flat per-action XP: harvesting a fruit tree
  at genuine peak ripeness (`fruiting_model.gd`'s real `hanging_at` state)
  earns more XP than an off-peak harvest of the same fruit — the player is
  rewarded for having correctly read *when*, not merely for having acted.
- **Village-feeding rewards**: successfully selling/trading real gathered
  food into a hungry village's `village_market.gd` (built earlier this
  session's NPC-economy pass) — keeping a real settlement fed through a
  real bad season is exactly the "prediction" pillar the design brainstorm
  landed on, made concrete and already-wired rather than abstract.
- **A new "Naturalist" skill-tree branch** (reusing `SkillTree`/
  `KeystonePassive` exactly as-is, no new progression system): nodes that
  pay off with real, visible ecosystem information rather than a flat stat
  bump — e.g. a keystone that reveals a cell's real land-health/vegetation-
  capacity numbers (this session's new persistent land-health mechanic) in
  the world UI. This is what makes "ecological literacy" legible as
  gameplay: the skill tree's payoff for investing in this branch is
  literally the ability to see more of the simulation the game already
  runs, not a bigger number.
- Deterministic, tested XP formulas throughout, same "no eyeballed
  constants" pillar the rest of this doc already commits to.

## Status / mechanisms

- ✅ XP/level/skill-point curve (`src/gameplay/experience_track.gd`, tested).
- ✅ XP earned on creature defeat (`Player.gain_experience`, scaled by creature
  level); XP bar + level/class readout in the HUD (`World._build_xp_bar`).
- ✅ Main menu (`scenes/main_menu.gd`): New Game / Host / Join / class picker,
  shown at launch with the world paused; class selection applies the
  `ClassArchetype` stat lens (`Player.apply_class`).
- ✅ Skill tree window (`scenes/skill_tree_window.gd`, toggle L) spends level-up
  points into `SkillTree` stat nodes and `KeystonePassive` keystones (gated by a
  minimum allocated-node count); `Player.allocate_skill`/`unlock_keystone` apply
  the bonuses live (max-health heals, attack-damage folds into swings). Rows you
  can't afford or haven't gated are greyed out.
- 🚧 Partial — XP from non-combat sources: two real "ecological literacy" triggers
  are wired (below), a first scoped slice of the gap rather than the whole
  crafting/foraging/quests roster.
  - ✅ **Peak-timed fruit harvest** — `FruitingModel.is_peak_ripe` is a real,
    tested definition against the model's own output (the plateau where
    `hanging_at` has reached its own `crop_potential`, before any of the crop
    has abscised — not an invented calendar band). `EarthChunkManager.
    harvest_peak_fruit_near` reads a nearby tree's real hanging-fruit/peak
    state; a NEW direct-from-the-tree pickup action (`Player.
    _try_harvest_peak_fruit`, the pickup key's fallback once the ordinary
    ground-item sweep finds nothing) grants the fruit and calls
    `EcologicalLiteracy.harvest_xp`. This had to be a genuinely new pickup
    path rather than reusing windfall-on-the-ground pickup: a fallen fruit
    has, by construction, already left the peak plateau (it fell BECAUSE it
    passed peak), so peak-timing could never be reachable through the
    existing ground-item sweep.
  - ✅ **Village-feeding sale** — `Player.sell_food_to_village` is a new
    player-initiated sale into a real `VillageMarket` (previously NPC-only,
    see `village_market.gd`'s own doc comment); "hungry" reuses
    `VillageMarket.can_buy_meal()`'s own real meaning (a whole meal's worth
    of stock, across every item, was available right before the sale) rather
    than an invented stock threshold. No gold changes hands — a village has
    no wallet of its own to pay from, so the reward for feeding a genuinely
    hungry settlement is the XP itself. Reachable via the existing trade key
    (T) as a fallback when no merchant is in reach.
  - Both `EcologicalLiteracy` totals are sized to match `Player.XP_PER_KILL`
    (6, a level-1 kill) at their skillful case — an internal-consistency
    anchor, tested and pinned, not eyeballed (see `ecological_literacy.gd`).
  - ⬜ Not built: crafting/quest XP sources; a true "prediction" mechanic (the
    player anticipating an UPCOMING peak/shortage rather than reading a
    already-current one); any UI feedback on the harvest/sale itself beyond
    the XP bar ticking (no "+6 XP — peak harvest!" toast).
- ✅ **Naturalist skill-tree branch** (`skill_tree.gd`'s `naturalist_1`/
  `naturalist_2` nodes, `stamina_regen`, gating the `land_sense` keystone in
  `keystone_passive.gd`). `land_sense` is deliberately unlike the other three
  keystones: empty `stat_name`/zero `bonus_amount` (a sentinel, not a bug —
  see the dict's own doc comment) instead of a stat bump. Its real payoff:
  once unlocked, `World._update_land_sense_label` shows a small always-on HUD
  label with the player's real, live `EarthChunkManager.land_health_near`/
  `vegetation_density_near` numbers — the exact figures
  `VegetationGrowthModel.effective_capacity`/`step_land_health` already run
  the simulation on, not a separate display-only stat.
  `SkillTreeWindow._keystone_label` special-cases a `stat_name`-less keystone
  to show its real `description` instead of a "+0.0" bonus line. This is a
  first scoped slice: it surfaces the land-health/vegetation-density numbers
  that already exist; it does not yet extend to any land-health-specific
  overlay beyond those two numbers, and there is no separate toggle (the
  label is always on once unlocked, per this pass's own scope call).
- ⬜ DNA-resonance class affinity, signature spell node (see [skills.md](skills.md)).
