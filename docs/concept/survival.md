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

#### The four triggers (mechanism spec)

Compiled from a design-brainstorm session (see [disease.md](disease.md) for
the sibling doc that built the real infrastructure this section now
spends): the bite trigger is the only one of the four actually wired up so
far, via `Player.apply_disease_bite`/`Sickness` (`src/gameplay/sickness.gd`)
— a real, tested, pure diagnose/treat model already exists and already
works, it just has one caller. The other three are that same model's
remaining, previously-unspecified triggers, not a new sickness system:

- **Open wounds, not just HP.** A hit above a real damage threshold — from
  a creature's `_try_attack` (`CreatureMarker`) or a botched swing on
  `Player._butcher_step` — leaves a real, visible wound distinct from raw
  health loss: a `DebuffStack`-tracked bleed that drains a little extra
  health/stamina per second until bandaged, mirroring `VenomModel`'s exact
  "a `*_per_second` rule feeding the generic stack" shape rather than a new
  bespoke module. A wound left unbound past a real duration threshold rolls
  the open-wound sickness through `Sickness.attempt_infect`, the same call
  the bite trigger already makes. Real grounding: an unclotted wound keeps
  losing blood over time rather than only at the moment of injury, and an
  untreated wound is a genuine infection vector (the actual mechanism
  behind real wound sepsis) — a second, slower threat layered on the acute
  one, not an invented game abstraction. A combat gash and a butchering cut
  become mechanically the same real thing, which is the honest answer to
  this project's own earlier open question about whether they should be.
- **Prolonged cold, as a real duration clock.** The warmth meter above
  already tracks `is_cold()`/`is_freezing()` from real ambient-temperature
  data (`WeatherModel.warmth_factor` via `EarthChunkManager.ambient_warmth`)
  and already accelerates fitness loss while cold — but nothing currently
  reads that signal for sickness. This adds the missing piece: an
  accumulating exposure timer that only advances while genuinely cold, and
  crosses into a real, diagnosable hypothermia sickness (its own
  shivering/fumbling symptom profile) once it runs out — not an instant
  temperature threshold. Real grounding: clinical hypothermia staging is a
  duration effect, not a pass/fail temperature check — the same reason real
  wind-chill charts post "time to hypothermia" in minutes, distinct from
  frostbite's separate, faster, extremity-specific mechanism.
- **Dirty water, as a situational hazard, not a flat rule.** Every water
  tile is equally safe to drink from today. This makes SOME water actually
  dangerous: drinking near a [carcass](carrion.md) `disease.md`'s own
  `DiseaseModel.carcass_contamination_chance` already marked contaminated,
  or at a watering hole a real overcrowded herd (`HerbivorePopulationModel`'s
  own local density-vs-carrying-capacity number, already read by
  `disease.md`'s herd archetype) has fouled, raises that specific water's
  contamination chance on the next `Player.drink()` — zero new simulation
  state, only a new consumer of two numbers that already exist. Real
  grounding: a carcass-fouled watering hole is a textbook real anthrax
  vector (the same African-savanna die-offs `disease.md`'s carrion
  archetype already cites), and a crowded herd fouling its own shared water
  with a real fecal-oral pathogen load is the actual, documented reason
  real livestock herds get rotated off a water source.
- **Resistance reflects what you've actually been living on.**
  `Player._disease_resistance()` feeds `Sickness.infection_chance`'s own
  `resistance` parameter — but today it reads nothing but current
  health/max_health, despite that parameter being explicitly designed to
  take more than one input. A rolling dietary-variety term (which
  [item](items.md) food categories were actually eaten recently, tracked
  alongside `SurvivalMeters.eat`) closes that gap: living off one food for
  days measurably erodes resistance to all four triggers above, a varied
  diet measurably strengthens it. Real grounding: real nutritional
  immunology — dietary diversity, not raw caloric sufficiency, measurably
  affects infection resistance (the actual reason historical scurvy/
  pellagra-type deficiencies tracked with elevated infection rates). Also a
  real new lever for [cooking.md](cooking.md)'s prepared-dish buffs (a stew
  combining several ingredient categories could earn a real resistance
  boost, not just a flat hunger-restore number) and for the Herbalist
  archetype's own day-to-day loop this section opened with.

Status:

- ⬜ All four triggers above — design spec only, not yet implemented. The
  underlying `Sickness`/`DiseaseModel`/`DebuffStack` machinery each trigger
  reuses is real and already proven by the one trigger (creature bite)
  `disease.md` wired up this pass.

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

- ✅ Resolved (not actually open): full sickness roster and triggers — see
  "The four triggers" above.
- Does sickness ever threaten to become contagious between nearby
  players/NPCs? Partially answered by [disease.md](disease.md)'s own
  creature-to-player zoonotic spillover (real, live) — genuine
  player-to-player/NPC contagion is still open, likely only relevant once
  multiplayer (roadmap Phase 5+) makes "nearby others" a meaningful
  concept.
- Exact debuff curve/stacking rules for compounding neglect (e.g. hungry +
  sick + exhausted at once) — needs numeric design.
- Exact tuned constants for each of the four triggers above (wound-bleed
  rate, cold-exposure duration threshold, water-contamination radius/chance,
  diet-variety window/decay) — this doc specifies the real SHAPE, per this
  project's own no-eyeballed-constants rule the numbers themselves get
  pinned by test at implementation time, not guessed at in a design doc.
