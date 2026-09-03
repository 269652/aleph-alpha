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

### Hunger and thirst keep the world's calendar (mechanism spec)

The meters are measured in the world's own day (`SeasonCycle.SECONDS_PER_DAY`,
four real hours — the same clock fruit phenology, tree growth and every
animal's appetite already keep), not in a private one of their own.
[seasons.md](seasons.md)'s "One clock, many readers" pillar already names
survival as a reader; this is that pillar honoured for the two meters that
were still on their own timer.

- **A full day of eating nothing empties you.** Hunger runs 0 → 1 across one
  in-game day, so one food item (`Player.EAT_HUNGER_RELIEF`, 0.4) is roughly a
  third of a day's need — 2.5 real meals a day, not dozens.
- **Thirst runs on two thirds of that**, so you go looking for water before you
  go looking for a meal. Real grounding: a person drinks several times for
  every time they eat, and dehydration is the faster of the two clocks by a
  wide margin.
- The old rates (0.004/0.006 per second) were 250 s and 167 s to full — about
  58 starvations per in-game day — because they were chosen against "how long
  before this nags a player" rather than against the calendar. Same two-clocks
  mistake `Snowfall`'s cover/thaw times documents about itself.
- Per this project's no-eyeballed-constants rule the spans are a tested
  function of `SECONDS_PER_DAY`, bracketed from both sides by test, not a
  number in a comment.

Status:

- ✅ Hunger/thirst spans derived from the world's day
  (`SurvivalMeters.SECONDS_TO_STARVE`/`SECONDS_TO_DEHYDRATE`), tested.
- 🚧 Crossing `is_starving`/`is_dehydrated` drives `fitness` decay, which is
  now a real movement debuff (see "What poor condition costs you" below). The
  mild `is_hungry`/`is_thirsty` thresholds still drive nothing — the ramp is a
  cliff at 0.85, not an escalation.

### What poor condition costs you (mechanism spec)

The "debuffs, not death" pillar above named four legal effect kinds; this is
the first of them actually wired. `SurvivalMeters.fitness` is already this
game's single accumulator of survival neglect — it falls while starving, while
dehydrated and while cold, and recovers otherwise — but until now **nothing
read it**, so hunger and thirst had no mechanical consequence at all and cold
had only the separate freezing movement slow.

- `condition_penalty.gd` is the missing consumer: one pure
  fitness → movement-multiplier curve, in the same "environment scales a
  movement multiplier" shape `Player._weather_speed_multiplier` and
  `_terrain_speed_multiplier` already use. It composes into
  `Player.current_speed_multiplier` alongside the water/weather/terrain
  factors.
- Deliberately **not** damage and deliberately not a health cap: the pillar is
  explicit that unmet needs never kill the player outright.
- Compounding is by construction, not by an invented stacking matrix: hungry
  AND dehydrated AND cold at once already drive the same meter down, so they
  compound through the one axis.
- No new tuned magnitude was invented. The worst-case multiplier **is** the
  value this codebase already committed to for its one existing severe
  exposure debuff, the freezing movement slow, which now references the
  module's constant so there is exactly one definition (pinned by
  `test_condition_penalty.gd`).
- Continuous survival state deliberately stays **out** of `debuff_stack.gd`.
  That model is duration-based (`{debuff_id, stacks, time_remaining}`, expiring
  on advance), a natural fit for discrete timed events like venom and an
  awkward one for a continuous state like hunger, which would have to be
  re-applied every frame with a meaningless duration just to stay alive.

Status:

- ✅ `fitness` → movement multiplier (`condition_penalty.gd`), composed into
  `Player.current_speed_multiplier`, tested.
- ⬜ The pillar's other three effect kinds (stamina regen, damage/accuracy,
  blurred vision). A damage hook exists (`Player._damage_buff_multiplier`) and
  would need only a magnitude decision; stamina regen would be invisible (see
  the stamina scope section — nothing spends stamina but sickness); blurred
  vision has no rendering hook at all.

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

- ✅ Warmth meter + thermoregulation (`survival_meters.gd`), cold accelerates
  fitness loss — and `fitness` now has a real consumer: `condition_penalty.gd`
  turns it into a live movement multiplier, so starving, dehydrated and cold
  all cost real speed. Until that landed, fitness was an accumulator with no
  reader anywhere in `scenes/` or `src/`.
- 🚧 Ambient warmth from climate × season × weather (`EarthChunkManager`),
  wetness chills.
- 🚧 Weather/freezing movement slow; warmth bar in the HUD.
- ⬜ Warmth as a distinct stacking debuff feeding a unified debuff model
  (`debuff_stack.gd` is built but not yet the survival backbone).
- ✅ Prolonged-cold sickness trigger — `cold_exposure.gd`, see "The four
  triggers" below. Cold now has a memory as well as a cost.

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

- **Open wounds, not just HP.** ✅ **Built 2026-09-03**
  (`src/gameplay/wound_model.gd`, `Player.step_wounds`,
  `CreatureMarker.step_wounds`). A hit above a real damage threshold — from
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

  As built, and two places it diverged from the text above. **The sepsis clock
  is not the bleed clock.** A wound stops bleeding in minutes and stays *open*
  for days, and it is the open wound rather than the bleeding one that gets
  infected — so `Player.seconds_wounded` keeps running after the `DebuffStack`
  entry has expired, and only `bandage_wounds()` clears it. Letting a wound
  clot is therefore not the same as binding it, which is what makes carrying a
  bandage worth doing; with the two clocks tied together a single wound could
  never go septic at all, because `DURATION_SECONDS` is deliberately shorter
  than `SECONDS_UNTIL_SEPSIS`. **And the same model runs on both sides**: a
  struck animal carries the identical stacks, bleeds by the identical rule, and
  is slowed by `WoundModel.speed_multiplier` at the same single movement choke
  point the herd-disease slow uses — which is what makes tracking a wounded
  animal worth doing (see [olfaction.md](olfaction.md)'s blood trail).

  `wounds.gd` is **superseded** by this and remains uncalled. It predates the
  spec, holds its own severity instead of riding the generic stack, and heals
  itself five times faster than it bleeds — so a wound there lasted about two
  seconds and cost about a fifth of a hit point. Left in place rather than
  deleted (this repo is co-edited by concurrent sessions); removing it is a
  tidy-up, not a behaviour change.
- **Prolonged cold, as a real duration clock.** ✅ **Built 2026-09-03**
  (`src/gameplay/cold_exposure.gd`, `Player.step_cold_exposure`). The warmth
  meter above already tracked `is_cold()`/`is_freezing()` from real
  ambient-temperature data (`WeatherModel.warmth_factor` via
  `EarthChunkManager.ambient_warmth`) and already accelerated fitness loss
  while cold — but nothing read that signal for sickness, so exposure had no
  MEMORY: warm up, and the afternoon in the sleet never happened. `ColdExposure`
  is the missing piece: an accumulating exposure clock that only advances while
  genuinely cold, advances `FREEZING_MULTIPLIER` times faster while freezing,
  and sheds at `RECOVERY_MULTIPLIER` of that rate while warm — below 1.0
  deliberately, because rewarming a chilled body runs at roughly half the rate
  cold strips heat from it, and that asymmetry is what gives the mechanic its
  memory. Real grounding: clinical hypothermia staging is a duration effect,
  not a pass/fail temperature check — the same reason real wind-chill charts
  post "time to hypothermia" in minutes, distinct from frostbite's separate,
  faster, extremity-specific mechanism.

  Because it is staged, the risk is too. `RISK_THRESHOLD` is the mild/moderate
  boundary: through the mild stage there is **no roll at all** — being chilly
  is not a small chance of hypothermia, it is no chance of it — and past it the
  exposure handed to `Sickness.infection_chance` *ramps*, so there is no single
  instant at which the player becomes at risk and staying out is genuinely
  worse than having just crossed the line. `SECONDS_TO_FULL_EXPOSURE` is not
  eyeballed against "how long before this nags a player" (the two-clocks
  mistake `SurvivalMeters`' own header documents) but bracketed as an ordering:
  far inside `SurvivalMeters.SECONDS_TO_STARVE`, because you die of cold in
  hours and of hunger in weeks, and still long enough to be weather you have to
  sit in rather than weather you walk through. The roll reuses the exact call
  the bite trigger already makes rather than inventing a second illness path,
  and respects the same one-sickness-at-a-time contract.
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

- ✅ **Prolonged cold** — `cold_exposure.gd` + `Player.step_cold_exposure`,
  stepped every frame alongside `_sickness_step`. Hypothermia is reachable,
  a mild chill never reaches it however long it goes on, and warming up in
  time is a real escape rather than a delay.
- ✅ **Open wounds** — `wound_model.gd`, wired on both sides
  (`Player.take_damage`/`step_wounds`/`bandage_wounds`,
  `CreatureMarker.take_damage`/`step_wounds`). Bleeds, slows, clots on its own,
  and goes septic if left unbound.
- ⬜ The other two triggers (dirty water, dietary resistance) — design spec
  only. The underlying `Sickness`/`DiseaseModel`/`DebuffStack` machinery each
  reuses is real and now proven by three triggers.

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
  sprint/climb mechanics themselves. Measured consequence, recorded so this is
  not mistaken for an oversight later: the only `spend_stamina` caller in the
  entire game is `Player._sickness_step`, so a healthy player's stamina is
  pinned at 1.0 and `is_exhausted()` can never fire. The exhaustion half of the
  "debuffs, not death" pillar is structurally unreachable until a traversal
  sink exists, which is exactly why `ConditionPenalty` deliberately has no
  exhaustion branch — it would be untestable-in-play dead code.

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
  sick + exhausted at once) — **partially answered, still open.** Compounding
  now happens through the single existing `fitness` axis: every unmet need
  drives the same meter down, so they compound by construction rather than
  through an invented stacking matrix, and the worst-case magnitude
  deliberately reuses the already-committed freezing-slow value rather than
  inventing a second number (`ConditionPenalty.WORST_SPEED_MULTIPLIER`). What
  remains genuinely open: which of the pillar's OTHER named effect kinds
  (stamina regen, damage/accuracy, vision) each need should also drive, and
  whether the mild thresholds (`is_hungry`/`is_thirsty`, as opposed to
  starving/dehydrated) deserve their own smaller drop rate — today the ramp is
  a cliff at 0.85, not an escalation.
- Exact tuned constants for each of the four triggers above (wound-bleed
  rate, cold-exposure duration threshold, water-contamination radius/chance,
  diet-variety window/decay) — this doc specifies the real SHAPE, per this
  project's own no-eyeballed-constants rule the numbers themselves get
  pinned by test at implementation time, not guessed at in a design doc.
