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

The creator's preview is a live animated vignette, not a static pose: the
authored character actually walks back and forth through a small grass patch,
swings their sword, and picks up a pebble to throw or kick away, alternating
between the two each time the loop repeats. It's the same `CharacterView` rig
the player and every NPC use, driven by a small, fixed, pure choreography
timeline (`CharacterPreviewChoreographer`) rather than a one-off animation —
reusing the real gameplay math for the throw/kick landing spot
(`HeldItemThrow.throw_distance_px`/`Kick.landing_position`) so the preview's
physics language matches actual play instead of inventing its own. Purely
presentational; nothing about class/stat selection changed.

## Skill tree

Levels grant points; the **skill tree window** spends them on
`SkillTree`/`KeystonePassive` nodes (already-built pure logic), whose
`total_bonus(stat)` feeds back into the player's derived stats. Small stat nodes
gate keystones (a minimum-nodes-spent requirement), matching [skills.md](skills.md).

## Status / mechanisms

- ✅ XP/level/skill-point curve (`src/gameplay/experience_track.gd`, tested).
- ✅ XP earned on creature defeat (`Player.gain_experience`, scaled by creature
  level); XP bar + level/class readout in the HUD (`World._build_xp_bar`).
- ✅ Main menu (`scenes/main_menu.gd`): New Game / Host / Join / class picker,
  shown at launch with the world paused; class selection applies the
  `ClassArchetype` stat lens (`Player.apply_class`).
- ✅ Skill tree window (`scenes/skill_tree_window.gd`, toggle K) spends level-up
  points into `SkillTree` stat nodes and `KeystonePassive` keystones (gated by a
  minimum allocated-node count); `Player.allocate_skill`/`unlock_keystone` apply
  the bonuses live (max-health heals, attack-damage folds into swings). Rows you
  can't afford or haven't gated are greyed out.
- ⬜ XP from non-combat sources (crafting/foraging/quests).
- ⬜ DNA-resonance class affinity, signature spell node (see [skills.md](skills.md)).
