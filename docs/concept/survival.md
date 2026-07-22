## Survival

ATLAS-inspired: food, hunger, stamina, wounds, fitness. The player needs to
eat, drink, and sleep; there's sickness and medicine to manage. See
[cooking.md](cooking.md) for how prepared food goes beyond raw hunger
restoration into real temporary buffs.

- **Debuffs, not death.** Unmet needs (hunger, exhaustion, untreated
  sickness) stack escalating debuffs — slower stamina regen, reduced
  damage/accuracy, blurred vision, movement penalties — but never kill the
  player outright. Actual death stays combat/environment-driven (falls,
  monsters, drowning), so a precious [life](death.md) is never spent on
  forgetting to eat; survival neglect just makes every *other* threat more
  dangerous. Exposure to [weather.md](weather.md) events (cold, wet) feeds
  this same debuff-stacking model.

### Body temperature & weather exposure (mechanism spec)

Concrete first pass at the "exposure to [weather.md](weather.md) events (cold,
wet) feeds this same debuff-stacking model" line above, and the temperature
dimension the core meters were missing.

- The player carries a **warmth** meter (1.0 = comfortable, 0.0 = freezing) that
  drifts toward an **ambient target** each moment. The target is the local
  climate temperature scaled by the current [season](seasons.md) and reduced by
  the current weather (rain/storm are colder than clear/cloudy) — one number
  standing in for "how cold it is around you right now."
- **Being wet chills you**: high `wetness` (from swimming or rain) pulls the
  warmth target down, so getting soaked in cold weather is worse than either
  alone — real evaporative/conductive heat loss.
- **Cold is a debuff, not a killer** (per the pillar above): while **cold**,
  overall condition (`fitness`) degrades faster — the same escalating-neglect
  model as hunger — and while **freezing** the player also moves slower.
  Warming up (clear/warm weather, drying off, a fire) reverses it. Death stays
  environment/combat-driven, never a direct tick from the warmth meter.

Status:

- 🚧 Warmth meter + thermoregulation (`survival_meters.gd`), cold accelerates
  fitness loss.
- 🚧 Ambient warmth from climate × season × weather (`EarthChunkManager`),
  wetness chills.
- 🚧 Weather/freezing movement slow; warmth bar in the HUD.
- ⬜ Warmth as a distinct stacking debuff feeding a unified debuff model
  (`debuff_stack.gd` is built but not yet the survival backbone).
- ⬜ Prolonged-cold sickness trigger (see Sickness & medicine below).

### Sickness & medicine

Distinct, diagnosable sicknesses rather than one generic "sick" flag —
this is the Herbalist archetype's ([classes.md](classes.md)) core day-to-day
loop:

- Each sickness has a specific trigger (drinking dirty/untreated water, an
  untreated open wound, prolonged cold exposure, a bite from a
  disease-carrying creature) and its own symptom/debuff profile.
- Curing a sickness requires identifying which one it is and brewing the
  matching remedy from gathered materials — real diagnostic +
  crafting depth, not "use potion, done." Feeds into
  [crafting.md](crafting.md)'s blueprint system as a recipe category.
- Herbalist skill nodes ([skills.md](skills.md)) improve diagnosis speed/
  accuracy and unlock more advanced remedies and preventative treatments.

### Stamina scope: movement only, not combat

Decided in a 2026-07-16 brainstorm against Valheim's stamina-gates-everything
model: stamina here is a **lighter, traversal-only** resource — it gates
sprinting, climbing, and swimming, but **not** combat swings/blocks. Combat
stays purely [combat.md](combat.md)'s cooldown-based ability system, kept
deliberately separate so the two systems don't fight each other for the same
tension: stamina is the survival/exploration friction layer, cooldowns are
the combat-skill-expression layer.

Status:

- ✅ The stamina meter itself (spend/rest/regen/`is_exhausted`,
  `survival_meters.gd`) is generic pure logic with no notion of what spends
  it, fully tested.
- ✅ Combat no longer touches stamina: attacking (`Player._perform_attack`)
  and blocking (`Player.take_damage`/`block.gd`) spend nothing from
  `SurvivalMeters` — `block.gd` exposes no stamina-cost API at all, and
  combat is purely cooldown-gated (`ATTACK_COOLDOWN`).
- ⬜ Sprinting and climbing don't exist as player mechanics yet (no input,
  no movement code), and swimming — which does exist as a movement mode —
  doesn't spend stamina yet (it only drains thirst via `drink()` and affects
  speed via water depth). None of the three traversal actions this section
  names are wired to stamina; that wiring is still to build, alongside the
  sprint/climb mechanics themselves.

### Open questions

- Full sickness roster and their triggers/symptoms — first-pass list needed
  before implementation.
- Does sickness ever threaten to become contagious between nearby
  players/NPCs? Interesting epidemic/quarantine layer, but likely only
  relevant once multiplayer (roadmap Phase 5+) makes "nearby others" a
  meaningful concept — flagged, not decided.
- Exact debuff curve/stacking rules for compounding neglect (e.g. hungry +
  sick + exhausted at once) — needs numeric design.
