# Playtest — 2026-08-25

A full hands-on session: booted the real build, made a character, played the
world (village, NPCs, combat, crafting, fishing, terraforming, weather,
seasons, night), and traced every symptom back to source before writing it
down. Findings are ordered by how much they cost, not by how easy they are
to fix.

**Setup.** Godot 4.7 stable, debug build, `--path` on this checkout. Intel
integrated GPU, GL Compatibility renderer, 1280×720 window. Driven through
real OS keyboard/mouse events with screenshots each step, so everything
below is what a player actually sees, not what a test harness reports.

**Caveat that applies throughout:** this was a *debug* build on integrated
graphics. Absolute frame numbers would be better on real hardware in a
release build. The relative findings (what degrades, what spams, what is
never wired) are hardware-independent.

---

## Outcome — what was fixed

Everything below was subsequently worked through: surveyed against the live
`main`, then implemented under strict red-first TDD, in four waves. **92 tracked
files changed (+6,925 / −514), 13 new test files, 3 new pure modules
(`condition_penalty.gd`, `input_latch.gd`, `seasonal_foliage.gd`), 2 new concept
docs (`hud.md`, `input.md`), and one file deleted as dead code.** Nothing has
been committed — it all sits in the working tree.

### Verified live, in the running game

| # | Finding | Before | After |
|---|---|---|---|
| 1 | Per-frame script error | 5,173 errors / 2.5 MB stderr in 5 min | **0 errors, 0 bytes** over a 10-min session |
| 3 | New Game destroys the save | silent wipe | confirmation dialog + **13 `.bak` files** written before the wipe |
| 5 | Survival rates | 15% → 43% hunger in one minute | derived from `SeasonCycle.SECONDS_PER_DAY`; 97% food after ten |
| 7 | Debug builds pinned to noon | `Sun elev 90.0°` at 02:11 | `Sun elev 45.3°` at 13:14, plus `/night` and `/time` |
| 9 | Seasons only reach the trees | winter trees on summer lawn | autumn canopies over a muted olive-brown lawn |
| 10 | Prompts over modals | "Talk (G)" drawn on the inventory | modal is clean |
| 12 | Console can't show its own output | one word per line, no scroll | wraps full width, scrolls to newest |
| 13 | Console dead key | first command failed to parse | `> ^/help` runs; the junk is stripped in the pure parser |
| 20 | HUD polarity flip | "Hunger 100% / Thirst 0%" | "Food 100% / Water 100%" — number and bar agree |
| 21 | Tooltips hide the emergent stats | "Raw Meat / Food / x5" | "Iron Sword / Weapon / **Iron — hard, keen** / **Damage: 15**" |
| 25 | Paperdoll is a head on a blue box | head + rectangle | a real rig, the player's own appearance, weapon in hand |

### Fixed and unit-verified

2 (export-safe sprite loading), 4 (hunger/thirst/cold now drive a real movement
penalty via the new `ConditionPenalty`), 6 (dead `WorldClock` deleted), 8 (snow
grain and the rain-streaks-during-snow bug), 11 (one shared message panel), 14
(Skills tab), 15a–e (creator diorama), 16 (elevation double-sampling, hillshade
double-gradient, `get_pixel` boxing, a wired streaming budget, and an
edge-latched input path so taps are no longer dropped between frames), 17
(`/ecotest`), 18 (per-species flyer ranges), 19 (the "Herbivore" placeholder),
22 (readable skill labels), 23 (trees *and* stone no longer built over), 26
(test fixture cost).

### Deliberately not done

- **The Path-of-Exile passive web** (22b) — `skill_tree.gd` has no edges, node
  coordinates or per-archetype split. A feature, not a fix. Tracked ⬜.
- **Sprint / climb as stamina sinks** (4d) — they do not exist as actions at
  all, which is *why* `is_exhausted()` gates nothing. Tracked ⬜.
- **Village house art** (23b) — the roof-shape system turned out to have landed
  separately while this was being written; only the stone palette and a ground
  shadow remain. Tracked ⬜.
- **Same-biome tile seams** (24, second half) — a real unspecced art problem.
  Tracked ⬜.
- **Full wild-crop dieback and reseed** — senescence-only was chosen
  deliberately (winter tint + growth scaled by `SeasonCycle.growth_modifier`);
  full dieback needs persisted dormancy state and a fourth art stage. Tracked ⬜.
- **Rebinding the console off the dead key** (13b) — the parser strip fixes the
  bug on every layout, and the toggle key is the owner's own muscle memory.

### Corrections — findings above that were wrong

Stated plainly, because the report should not be read as if all 26 held up:

- **"Snow draws over water" does not reproduce.** The ocean guard already
  exists and is deliberate. (It was untested, which is why it looked absent.)
- **"Flowers ignore the season" was mostly already fixed.** One of eight
  species genuinely blooms in winter. The real residue is that withered art is
  baked at sprite-creation time.
- **The hard water/land staircase is an explicit spec decision**, not a defect —
  `terrain_borders.md` rules water out of base-layer blending on purpose. Only
  the same-biome seams are a real gap.
- **The creator's grass is not out of *scale*, it is out of *density*** — a
  clump on ~100% of clear cells against the real world's `SEED_CHANCE` of 0.20.
- **Idea 2 above contradicted the spec.** It proposed wiring `is_starving()` to
  HP drain; `survival.md`'s first pillar is "**Debuffs, not death** — unmet
  needs stack escalating debuffs but never kill the player outright." The
  implementation follows the spec, not the idea.

### New problems found while fixing

- `PickableSeed` was a second victim of finding 1, not just `LiftableStone`.
- **`EarthChunkManager.step_wild_crops` had no production caller at all** — wild
  crops have never grown or spread in any real session. Now called.
- The entire seasonal-ground chain was built, tested and **never called** until
  the last wave; unit-green features with no caller are a recurring shape here.
- `try_plant_seed_at` returns `true` unconditionally even when rooting is
  refused. Left alone — it changes a contract.
- `test_earth_chunk_manager.gd` has three pre-existing failures unrelated to any
  of this, one of which looks like a real biome/rooting disagreement.

---

## P0 — costs the most right now

### 1. A per-frame script error fires on every frame you stand near a stone

`Player.nearest_kickable_dropped_item_near` walks
`get_tree().get_nodes_in_group(DroppedItem.GROUP_NAME)` and reads
`item.item_stack` on every member. `LiftableStone` deliberately joins that
same group (so `pick_up` works on it) but is a plain `Node2D` with no
`item_stack`, so every stone in range throws:

```
SCRIPT ERROR: Invalid access to property or key 'item_stack'
  on a base object of type 'Node2D (liftable_stone.gd)'.
   at: Player.nearest_kickable_dropped_item_near (scenes/player.gd:1773)
       _update_interaction_prompt (scenes/world.gd:1366)
       _client_process (scenes/world.gd:3216)
```

`_update_interaction_prompt` runs every frame, so this is one full
GDScript backtrace written to stderr **per frame, per nearby stone**.
Measured: **5,173 errors and 2.5 MB of stderr in about five minutes of
ordinary play** — and stone is one of the densest things in the world.

It also drowns the log: this single error was 100% of the script errors in
both sessions, so any *other* runtime error is now invisible.

**Fix.** Skip nodes that aren't dropped items, the same duck-typed way
`EarthChunkManager.nearest_liftable_stone_near` already screens on
`has_method("pick_up")`:

```gdscript
for item in get_tree().get_nodes_in_group(DroppedItem.GROUP_NAME):
    if not (item is DroppedItem):
        continue
    ...
```

### 2. Illustrated player art and illustrated crops will not render in an exported build

Two test files fail today with the same engine error — a pattern that is
already treated as known cosmetic test noise. The *test failure* is cosmetic.
The reason for the warning is not:

```
Loaded resource as image file, this will not work on export:
  'res://assets/sprites/player/hero_composite.png'
  'res://assets/sprites/player/head.png'
  'res://assets/sprites/plants/carrot.png'
```

`SpriteSheetLoader.load_image()` exists precisely to prevent this, and its
doc comment spells out both consequences (the raw PNG does not ship in an
export; GUT counts the warning as a failure). Four call sites never adopted
it:

- `src/rendering/illustrated_character_sprite.gd:203` — single-pose parts
- `src/rendering/illustrated_character_sprite.gd:506` — `hero_composite.png`, the player's entire body
- `src/rendering/illustrated_character_sprite.gd:869` — `head.png`, the player's face
- `src/rendering/illustrated_crop_sprite.gd:187` — carrot/potato

So in a shipped build the hero's body, head, and the illustrated crops all
take the missing-image path. Compounding it, `git status` shows
`assets/sprites/player/hero_composite.png.import` is **untracked** — a fresh
clone has no import metadata for that sheet at all.

**Fix.** Route those four calls through `SpriteSheetLoader.load_image`, and
commit the `.import` sidecars.

### 3. "New Game" destroys the existing save with no confirmation

`World._on_menu_start_requested` calls `wipe_memory_store`,
`wipe_household_store`, `wipe_contract_store`, `wipe_market_store`,
`wipe_institution_store`, `wipe_world_boss_store` and `wipe_world_clock`
(`scenes/world.gd:540-558`), then autosave overwrites `player_save.bin`.
There is one save slot, no backup, no "are you sure", and no way back.

Every emergent thing the project is *about* — remembered events, households,
contracts, markets, institutions, promoted world bosses — is gone on one
misclick from the main menu.

*I triggered this myself during the session; see "What this session changed"
at the bottom.*

**Fix.** Confirmation dialog when a save exists, and/or write
`player_save.bin.bak` before the first autosave of a new world. Named slots
are the real answer, but a confirm + backup is an afternoon.

---

## P1 — significant, visible, or misleading

### 4. The player's survival meters drive nothing

`SurvivalMeters` exposes `is_starving()`, `is_dehydrated()`, `is_hungry()`,
`is_thirsty()`, `is_exhausted()`. A repo-wide search finds **zero call sites
for any of them** outside the module and its own tests. The only predicate
anything reads is `is_freezing()`, used once, for a 25% movement penalty
(`scenes/player.gd:1158-1163`). `stamina` is read only to draw its own bar.

Played out: hunger and thirst both sat pinned at 100% for minutes with full
health and no debuff, no damage, no warning. Eating one raw meat moved
hunger 100% → 60% and nothing else changed.

The contrast is sharp — creatures (`CreatureNeeds.is_hungry/is_thirsty`) and
villagers (`NpcNeeds.is_hungry` → `NpcEconomy` buying food at the market)
both act on their needs properly. **The animals are better simulated than
the player.**

`docs/progress.md`'s Survival section currently reads "Core survival meters
are now real and wired into live gameplay" and flags only *stamina* as
unwired. Hunger and thirst are equally unwired on the consequence side —
they're written and drawn, never read. Worth correcting there.

### 5. Survival rates are out of scale with every clock in the game

| Constant | Value | Time to 100% |
|---|---|---|
| `SurvivalMeters.HUNGER_RATE_PER_SECOND` | 0.004 | 250 s (4 min 10 s) |
| `SurvivalMeters.THIRST_RATE_PER_SECOND` | 0.006 | 167 s (2 min 47 s) |

Against the calendar the world actually runs on
(`SeasonCycle.SECONDS_PER_DAY = 14400`, a 4-hour in-game day) that is
**≈58 starvations per in-game day**. Against the day/night cycle the
*lighting* runs on (real-world UTC, so 86,400 s) it is **≈346**.

Observed live: a fresh character went 15% → 43% hunger in the first minute
and hit 100% inside four. `docs/progress.md` says the rates were "retuned
much slower (pinned by a test: a minute of play no longer pushes you into
hungry/thirsty)" — technically true from a zero start, but a new character
does not start at zero and crosses `HUNGRY_THRESHOLD` in about 90 seconds.

This is exactly the "two clocks" mistake `snowfall.gd`'s own comments warn
about, and it should be fixed the same way those were: derive the rates
*from* `SeasonCycle.SECONDS_PER_DAY` as a tested function ("a full day of
not eating starves you"), not as free-floating constants.

### 6. There are three different day lengths, and one is dead code

| Source | Day length | Drives |
|---|---|---|
| Real-world UTC (`Time.get_datetime_dict_from_system`) | 24 h | sun elevation, hillshade azimuth, the HUD clock |
| `SeasonCycle.SECONDS_PER_DAY` | 4 h | seasons, phenology, tree growth, fruiting, life cycles |
| `WorldClock.DAY_LENGTH_SECONDS` | 10 min | **nothing** |

`src/world/world_clock.gd` is referenced only by
`tests/unit/test_world_clock.gd`. Nothing in `src/` or `scenes/` imports it.
It is a tested, maintained, never-used class whose constant contradicts the
two real clocks — delete it or wire it.

The 6× gap between the other two is real and visible: plants live six days
for every sunrise, and because a new world rolls a random age
(`randomize_world_age`), the season and the sun's declination are decoupled.
I started a new game on 25 August and got Autumn.

### 7. Debug builds never show night — so nobody is playtesting half the world

`World.always_day_for(force_day, env_value, is_debug)` returns `is_debug`
when the env var is unset. Running from source therefore pins
`Sun elev 90.0°` around the clock, which is what I saw for the first hour:
full midday lighting at "Local 02:11". `/day` exists; there is no `/night`.
The only way out is `AA_DEBUG_ALWAYS_DAY=0` in the environment.

Setting it, night renders correctly and looks good (`Sun elev -17.4°`, a
proper blue night palette). But it means darkness, torches, night-active
creatures, star charts and the cold/night interaction are all invisible in
the only build anyone runs day to day.

**Fix.** Default debug to the real cycle; add `/night` and `/time <hh:mm>`
to the console so "show me midday" stays one keystroke away.

### 8. Snow renders as square patches of white pixel noise

At the lowest depth band, snow is `BAND_COVERAGE[0] = 0.45` of pixels at
`BAND_WHITENESS[0] = 0.80`, and `onset_offset_for(global_x, global_y)`
varies **per tile**. The result is a checkerboard of hard-edged squares,
each filled with ~50% pure-white static, against fully bare neighbours. It
reads as texture corruption rather than snow, it draws over water, and rain
streaks keep falling during a snowstorm.

**Fix.** Sample the onset offset from smooth low-frequency noise at
sub-tile scale so the snow line meanders instead of snapping to the tile
grid; and tint the shallow bands toward the ground colour (frost) instead of
near-white, so 45% coverage reads as a dusting.

### 9. Seasons only reach the trees

Forcing winter turns deciduous canopies bare and snow-caps the pines —
genuinely good. Everything underneath ignores it: the grass stays full
summer green, tall grass stays lush, flowers keep blooming, and a wild
potato is still standing and harvestable. Bare winter trees on a bright
green lawn is the single most jarring frame in the game.

Ground cover is the highest visual return per unit of work in this list.

### 10. World-space prompts draw on top of modal windows

The "Talk (G)" / "Tall Grass — Harvest (Space)" / "Boulder — Smash" prompt
renders *over* the inventory, crafting and skill-tree panels. Seen on four
separate occasions. The prompt needs to live under the UI canvas layer, or
hide while a modal is open.

### 11. Dialogue, fishing and trade messages are unbacked white text over the world

"Wynin the guard greets you warmly…", "Casting — wait for a bite", "No food
to sell." are all drawn straight onto the world with no panel, no shadow, no
outline. Over a light wall they're hard to read; over snow they are
completely invisible. Two messages can also overlap each other.

**Fix.** One shared message panel with a translucent background, the same
treatment the creature panels already get.

### 12. The dev console cannot display its own output

Two compounding bugs in a tool the whole project is debugged with:

- `_output_label` sits in a `ScrollContainer` with horizontal scrolling left
  on, so its minimum width is the widest single word and **every line wraps
  to one word**. "Dev console ready. Type /help for commands." renders as
  six lines.
- `MAX_LOG_LINES = 12` counts *logical* lines, which become dozens of visual
  ones, and the scroll container never scrolls to the newest entry — so
  command output lands below the fold and is never seen.

Net effect: `/help`, `/history`, `/why`, `/emergence`, `/settlement` and
every other read-only command is unreadable. I could only verify commands
that change something visible on screen.

**Fix.** `scroll.horizontal_scroll_mode = SCROLL_MODE_DISABLED`, give the
label `size_flags_horizontal = SIZE_EXPAND_FILL`, and scroll to bottom on
append.

### 13. The console toggle key types a character into the console

Opening the console with the default binding leaves a stray character in the
input box, so the first command of every session fails to parse — I got
`^/spawn boar 2`. On a German layout the key left of `1` is the `^` dead
key, which Windows holds and emits on the *next* keystroke, after
`toggle()`'s `_input.clear()` has already run. Anyone on a German keyboard —
including this repo's owner — hits it every session.

**Fix.** Strip anything before the first `/` in `_on_text_submitted` (or in
`ConsoleCommandParser.parse`), and/or move the default binding off a dead
key such as `F1`.

### 14. The Skills tab in the character creator is unusable

Selecting "Skills" collapses the whole tab body to roughly a 130 px column —
text wraps to two or three words per line, the tab strip shrinks to a single
tab plus scroll arrows, and **the shared skill pool, the entire point of the
tab, is never visible at all**. There is ~800 px of unused width to its
right.

Likely cause: `_build_skills_tab`'s `col` (`scenes/main_menu.gd:557`) never
sets `size_flags_horizontal = SIZE_EXPAND_FILL`, and it nests a
`ScrollContainer` (minimum size ≈ 0 on both axes) inside the outer
`ScrollContainer` the tabs already live in.

The feature request this tab answers — "view each class's skills before
creating" — currently doesn't work.

### 15. The character-creator preview diorama is broken

The preview panel shows the hero as a small figure inside a hard-edged blue
rectangle, surrounded by grass tufts three to four times his height, on a
near-black void with no ground, and trees clipped by the frame. All seven
class thumbnails above it are the same sprite.

`test_character_preview_diorama.gd` is also one of the two currently failing
test files (finding 2). This is the first screen a new player sees.

---

## P2 — quality, polish, and things that undercut the pitch

### 16. Performance

| State | FPS |
|---|---|
| Fresh instance, standing still | 20–26 |
| Walking (chunk-streaming dips) | 6–8 |
| During `/ecotest` | 2–3 |

Working set ~1 GB, private bytes ~3.8 GB, ~98% of one core, single-threaded.
The traversal dips are periodic and line up with chunk boundaries —
streaming looks synchronous on the main thread. Below ~10 FPS the game
starts dropping keypresses outright: a 140 ms tap can fall entirely between
two polled frames.

Finding 1 is a free win here — thousands of formatted backtraces per minute
is real work — but it is not the whole story, since a clean instance with no
stones nearby still sat at ~20.

### 17. `/ecotest` cannot reach its target, and asking for more makes it worse

`TimeLapse` hands the ecology at most
`MAX_SLICES_PER_FRAME (4) × SLICE_SECONDS (240) = 960` simulated seconds per
frame. A year is `SECONDS_PER_YEAR = 691,200 s`, so **a year needs at least
720 frames no matter what you type**. Running the time-lapse drops the game
to 2–3 FPS, which puts a year at roughly five real minutes.

I asked for `/ecotest 12` (a year every 12 s) and saw no season change at
all in 15 s — the canopies stayed autumn. There's a feedback loop: the
faster you ask, the more work per frame, the lower the frame rate, the less
simulated time actually advances.

**Fix.** Advance the *calendar* at the requested rate independently of how
much per-frame ecology stepping keeps up — seasons and canopies are what
you're watching — and scale the slice budget to the achieved frame time
instead of a fixed count.

### 18. Ambient flyers are the one genuine fixed spawn table

`AmbientFlyerRenderer` picks from a global list — `monarch`, `swallowtail`,
`blue_morpho`, `bee`, `sparrow`, `robin` — with no biogeography at all. I
watched a **Monarch** (North America) flutter past at 52.5°N in Germany, and
`blue_morpho` (Neotropical rainforest) is in the same pool.

This is the only creature category I found that contradicts *"a boar is
where boars can actually thrive right now"* — the ecosystem already computes
habitat suitability; the flyer pool just doesn't ask.

### 19. "Herbivore" shows up as a creature's name

The generic fallback species leaks into the player-facing creature panel:
`Herbivore Lv.5`, alongside `Boar Lv.1` and `Wolf Lv.2`. Either give the
generic profile a real species name or filter it out of spawn.

### 20. The survival HUD flips polarity mid-panel

Four rows, two conventions:

- `Hunger 100%` / `Thirst 0%` — the *deficit*: higher is worse.
- `Warmth / Cold / Freezing %` — the *resource*: higher is better.
- All four bars fill as things get *better*.

So `0%` means "good" on one row and "bad" on the next, and the number moves
opposite to the bar beside it on two of them. Relabel food and water as
reserves (`Food 40%`, `Water 100%`) so every row and every bar points the
same way, matching the health bar.

### 21. Item tooltips hide the one thing that makes this game different

The whole pitch is *"we do not hardcode 'iron sword = 12 damage'"* — stats
emerge from real material properties and shape. The inventory tooltip says:

```
Raw Meat
Food
x5
```

No mass, no damage, no nutrition, no durability, nothing derived. A player
can never see that a sword's damage came from iron's density and a blade's
volume, so the deepest system in the project is invisible at the exact
moment it would land. The crafting cards *do* name their ingredients on
hover, which is good — the gap is the output's computed properties.

**This is the cheapest big win in the document.** The numbers already exist
(`Item.mass_kg`, `MaterialProperties.mass_kg_for`); they just need a line
each in the tooltip.

### 22. The skill tree is a flat list of internal identifiers

`Vitality 1 +10.0 max_health (1 pt)`, `Butchering 1 +1.0 meat_yield (1 pt)`
— raw field names in player-facing text, in a left-aligned list occupying
half the panel, over a semi-transparent background that lets the world show
through. The README promises "a Path-of-Exile-style passive web". The
creator's own honest note ("Every class currently draws from this same
shared pool") is the right tone; the window should say the same.

### 23. Buildings are flat untextured slabs — and trees grow through them

Village houses are dark grey brick rectangles seen from above, with no
roofline, eaves, shading or shadow, sitting hard-edged on the grass. Next to
the main menu's key art (which is lovely) the gap is stark. Separately, a
tree spawns **inside** a building's stone floor, canopy drawn over the
masonry — house placement checks for water (`_footprint_is_dry`) but tree
placement doesn't check for houses.

### 24. Water edges and tile seams

Lakes are hard staircase tile boundaries against grass with no shoreline
blend, and single-tile ponds appear as isolated blue squares in open
grassland. Grassland itself shows visible rectangular seams where adjacent
tiles differ slightly in tone, so the ground reads as a grid.

### 25. The equipment paperdoll is a floating head on a blue rectangle

In the inventory window, the character preview is a head sprite above a
plain blue box — no torso, arms or legs — while the same character renders
correctly in the world two feet away.

### 26. Test suite runtime

A headless run reached test file **82 of 760 after roughly 23 minutes of
CPU** and was still inside `test_earth_chunk_manager.gd`, which alone had
been running for over fifteen of those minutes. I stopped it rather than let
it finish. Of what completed: 2 failed (finding 2), 1 was risky —
`test_set_wind_strength_is_a_harmless_no_op` asserts nothing.

The bottleneck is specific and fixable: every test that calls
`manager.update(tile)` pays real chunk generation *plus* real sprite and
texture generation for every species it spawns, once per test in
`before_each`. That is a fixture problem, not a slow-computer problem —
a shared cached manager, or a stubbed elevation source and sprite generator,
would take that file from tens of minutes to seconds.

Until then the suite can't be run end-to-end in one sitting without excluding
that file, which is worth writing down in `CONTRIBUTING.md` next to the TDD
rule, since strict red-first only works if the red is cheap to see. For a project committed to strict red-first TDD, a
suite nobody can run end-to-end in a sitting is a process risk worth
measuring properly and splitting (fast unit tier vs. slow world-generation
tier).

---

## What genuinely works well

Worth stating plainly, because the list above is long and the good parts are
load-bearing:

- **Movement modes read instantly.** Walking → swimming, `Speed: 100%` →
  `22%`, a visible swim animation, ripples, fish scattering around you.
  Snow drops you to 48%. Weather and terrain both feed the same multiplier
  and you *feel* it without reading the HUD.
- **Rain made worms come out of the ground.** No timer fired; the soil got
  wet. That is the design pillar working, unprompted, in the background.
- **NPC dialogue has voice.** "Wynin the guard greets you warmly…",
  "Rhoel the hunter grins, unbothered: 'Ha! A stranger…'" — role, name and
  temperament, procedurally, and it does not read as filler.
- **Illustrated art, where it's wired, is genuinely good.** Cherry blossom
  in spring, bare branches and snow-laden pines in winter, autumn oranges at
  night, the wolf, the boars, the hero. The trees carrying the season is a
  real pleasure.
- **Terraforming works and is legible.** Q and B cut and fill visible
  terrain, and the dug channel stayed dug (and stayed snow-free) across a
  season change.
- **End-to-end crafting works.** Gather → recipe affordability lights up →
  craft → the tool works: I made a fishing rod from sticks and fibre and the
  bobber went in the water.
- **The world is real.** Lat 52.5 / Lon 13.4, a village 100 km north with
  houses, a market stall, wells and villagers on schedules — found by
  simulation, not placement.
- **Loading has honest progress.** "Preparing a new world… (18 / 25 chunks)"
  beats a spinner.
- **`docs/progress.md` is unusually honest.** It already says "dying
  currently costs nothing" and "stamina is not yet wired to anything". Most
  of what I found was either already tracked there or is a genuine gap
  between doc and code — not spin.

---

## Ideas, in rough order of value per unit of work

1. **Put the emergent numbers in the tooltip** (finding 21). Mass, damage,
   nutrition, durability. One line each. It turns the project's deepest
   system from invisible to the reason someone keeps playing.
2. **Wire the survival predicates that already exist** (finding 4).
   `is_starving()` → HP drain, `is_dehydrated()` → the same, `is_exhausted()`
   → gate sprinting. The pure logic and its tests are already written; only
   the call sites are missing.
3. **Derive survival rates from `SeasonCycle.SECONDS_PER_DAY`** (finding 5),
   as a tested function rather than a constant — the house rule for tuned
   values, applied to the one place it isn't.
4. **Ground cover that carries the season** (finding 9). The trees already
   prove the pipeline; grass, flowers and crops need to read the same clock.
5. **Flip the debug day default and add `/night` + `/time`** (finding 7).
   Half the simulation becomes visible for a one-line change.
6. **Make the console readable** (findings 12–13). Everything else gets
   debugged through it.
7. **Give the flyer pool biogeography** (finding 18) by asking the
   suitability model the ecosystem already computes. Small change, and it
   removes the one place the world contradicts its own thesis.
8. **Death that costs something** (`docs/concept/death.md`).
   `lives_tracker.gd` and `corpse.gd` are already written and tested;
   `Player._respawn()` just doesn't consult them. The single biggest stake in
   a survival game currently costs three seconds.
9. **Raw meat should be a gamble.** `sickness.gd` exists, tested and
   unwired. Eating raw meat is the most natural first trigger in the game
   and it would give cooking a reason to exist.
10. **One shared world-message panel** (finding 11), under the modal layer
    (finding 10).

---

## What this session changed

Nothing in `src/`, `scenes/` or `assets/`. Two side effects to be aware of:

- **`player_save.bin` was overwritten** (finding 3). Clicking "New Game"
  wiped the emergence stores and autosave then replaced the save. There was
  no backup to restore from. The character that was there before this
  session was a level 1 Warrior with 0 gold, so little appears to have been
  lost — but the emergence stores (`emergence_*.bin`, now 12-byte empty
  headers) and all but one `chunk_modifications` entry are gone.
- This document was added at `docs/playtests/2026-08-25-full-session.md`.
