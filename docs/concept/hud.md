# HUD

This doc specifies the on-screen readouts the world draws over itself: the
survival panel, the transient message banners, the world-space interaction
prompt and hover tooltip. It exists because these grew one at a time, each
locally reasonable and collectively inconsistent — bare white text that
vanished over snow, two banners pinned to the same y offset, and one panel
that flipped polarity halfway down.

The HUD is not a separate subsystem with its own model. It is a *view* of
models that are specified elsewhere ([survival.md](survival.md),
[taming.md](taming.md), [trade.md](regional_trade.md),
[easter_eggs.md](easter_eggs.md)). What this doc pins is how those models are
allowed to appear.

## Design pillars

1. **Legible over every terrain, snow included.** Nothing that carries meaning
   may be drawn as bare text over the world. A message sits on an opaque card,
   not on whatever happens to be under it. The one shared card is
   `UiTheme.panel_stylebox()` (`PANEL_BG`, alpha 0.98, with a border) — the
   same card the survival panel and `CreaturePanel` already use, so "legible"
   is one decision made once rather than a per-widget judgement call.

   The same rule now covers **selection**: a control that is toggled ON
   wears `UiTheme.selected_button_stylebox` — the gold `ACCENT`, thicker
   than an ordinary border, over a background that lifts rather than sinks.
   Godot's own `pressed` stylebox is a shade *darker* than normal in this
   theme (about 5% of value), which measured as invisible over a dark card
   when the build palette was first rendered
   (`tools/probe_build_palette.gd`). It is applied per control rather than
   in the shared `Theme`, because `pressed` there also means a momentary
   click on every ordinary button in the game, and marking those gold would
   make every button in every window flash as selected while held.
2. **A number and the bar beside it always mean the same thing, and full is
   always good.** Every meter is shown as a **reserve**, never as a deficit,
   whichever way the model happens to store it internally.
3. **The world's own hints never cover a window the player opened.** A prompt
   about the world *behind* a modal is noise even where it does not overlap.
4. **A card sizes to its own content, and cards stack in columns.** No card is
   pinned to a box its own text can outgrow, and no card is positioned against
   a neighbour's height. Overlap is structurally impossible rather than
   avoided by hand-picked constants — the rule the message stack already
   followed, applied to the whole HUD.

## Mechanism spec

### One CanvasLayer, so sibling order is draw order

Every HUD node in `scenes/world.gd` is a child of the same `$UI` CanvasLayer.
Within one CanvasLayer, draw order is sibling order — and `_ready()` builds
the inventory/crafting/skill windows *before* the world-space floaters, so the
floaters paint on top of an open window. "Talk (G)" and a tooltip about a tree
behind the inventory drew straight over the inventory (reported).

The rule is **not** to reorder the layers but to hide the floaters:

> Anything positioned in WORLD space — the interaction prompt, the hover
> tooltip, the message stack — is hidden whenever `_any_gameplay_window_open()`
> is true. `World.world_hint_visible_for(can_show, window_open)` is the single
> pinned expression; `_any_gameplay_window_open()` is the same predicate
> `EscapeAction.action_for` already treats as "a modal is open".

That predicate is deliberately **not** widened:

- The **settings overlay** pauses the tree (`get_tree().paused`), so
  `_client_process` stops running and the floaters freeze rather than update.
  Freezing is acceptable; widening the predicate would change what
  `EscapeAction` means.
- The **dev console** is a small bottom strip that overlaps no floater.

### The message stack

Fishing, taming, trade, talk and Easter-egg sightings used to be five
independent, absolutely-positioned, background-less `Label`s at hand-picked y
offsets (120, 144, 144, 168, 210). Two of them shared 144, so a trade message
and a taming message drew through each other; none had a background, so all
five disappeared over snow.

They are now **one `VBoxContainer`**, anchored `PRESET_CENTER_TOP` at
`World.MESSAGE_STACK_TOP` / `MESSAGE_STACK_WIDTH`, whose children are
`PanelContainer` cards themed by the shared `_ui_theme`. A hidden child takes
no room in a VBox, so whatever is showing simply stacks and **overlap is
structurally impossible rather than avoided by hand-picked constants**.

Fixed top-to-bottom order, pinned by `World.message_banner_lines` so a message
never moves under the player's eye depending on which others happen to be
showing:

| # | Banner | Source |
|---|--------|--------|
| 1 | Fishing | `Player.fishing_message` |
| 2 | Taming | `Player.lasso_message` |
| 3 | Trade | `Player.trade_message` |
| 4 | Talk | `Player.talk_message` |
| 5 | Easter-egg sighting | `World`'s own message + countdown |

`_set_message_banner(banner, message)` is the only way a banner's text is set;
it hides the whole **card** when the message is empty, so nothing can leave a
blank card holding a gap open. The Easter-egg banner is the one per-banner
difference: `EASTER_EGG_MESSAGE_COLOR`, cooler and dimmer than `UiTheme.TEXT`,
so an ambient glimpse reads as something the world said rather than a result
of something the player just did.

### Meter vocabulary: shown as reserves, stored as deficits

`SurvivalMeters` stores **hunger** and **thirst** as deficits (rising toward
1.0 = worse — that is how the model integrates them) and **stamina** and
**warmth** as reserves (1.0 = good). The panel used to fill all four *bars*
with the reserve but print the raw stored value for all four *labels* — so a
starving player read **"Hunger 100%" over an EMPTY bar**, two rows above
**"Warmth 100%" over a FULL one**, meaning the opposite.

The HUD shows all four as reserves, labelled for what is **left**:

| Model field | Stored as | Shown as | Label |
|-------------|-----------|----------|-------|
| `hunger` | deficit | reserve | **Food** |
| `thirst` | deficit | reserve | **Water** |
| `stamina` | reserve | reserve | **Stamina** |
| `warmth` | reserve | reserve | **Warmth** / **Cold** / **Freezing** |

Two pure functions carry the rule, so the number and the bar are the same
value *by construction* rather than by two lines agreeing to stay in step:

- `World.reserve_for_deficit(deficit)` → `clampf(1.0 - deficit, 0, 1)`
- `World.meter_label_text(name, reserve)` — takes the **same** reserve
  fraction that fills the bar beside it.

The warmth row keeps its three-way state name (`Freezing`/`Cold`/`Warmth`,
from `SurvivalMeters.is_freezing()`/`is_cold()`), which is a *label* change
only — the percentage under it is still the same reserve the bar shows.

### The top-left strip: the player's half is a card, the diagnostic half is opt-in

The strip at `(8, 8)` was one bare `Label` -- `$UI/DebugLabel`, still carrying
its `.tscn`-authored `"Loading..."` placeholder -- holding eight fields in a
single `%`-formatted string:

```
FPS 87   Lat 48.0 Lon 7.9   Local 14:32   Sun elev 41.3°   Summer · Clear   Mode: walk   Speed: 100%
```

That mixes two audiences in one line. *Local 14:32*, *Summer · Clear*,
*Mode: walk* and *Speed: 100%* are things the player plays with. *FPS*,
*Lat/Lon* and *Sun elev 41.3°* are things a developer debugs with -- a player
who has never opened this repo cannot act on any of them. And being a bare
`Label`, the whole line broke pillar 1: white text over whatever terrain
happened to scroll under it.

They split along that seam:

- **The world-clock card**, on the shared `UiTheme.panel_stylebox()`: the
  time, the phase of the day, the season, the weather, and how the player is
  moving. Always visible. `HudReadouts.world_clock_lines` is the pinned pure
  half. It lands **top-right, under the minimap** rather than back in the
  corner it came from — where you are and when you are are one thought, and
  the top-left column is already the player's own state (health, XP, land
  sense, creature panels).
- **The diagnostics strip**: FPS, latitude/longitude, sun elevation in degrees,
  **bottom-right** — the one free corner, and toggled over the top-left column
  it would cover exactly the health and meters the player was watching when
  they reached for the key. **Hidden by default**, toggled with the rebindable
  `toggle_diagnostics` action (default **F3**), and not even written while
  hidden, so a player who never presses it pays nothing for it.
  `HudReadouts.diagnostics_lines` is its pure half.

A diagnostic that is off until asked for is the rule
[`RiverFlowShader`'s raw-across channel](../../src/rendering/river_flow_shader.gd)
already states for itself ("a diagnostic must never ship on"); this applies it
to the one diagnostic that did ship on.

**Why a separate `HudReadouts` module rather than more statics on `World`.**
The four pure HUD decisions that exist today (`message_banner_lines`,
`world_hint_visible_for`, `reserve_for_deficit`, `karma_display_text`) are
statics on `World` because they were each one function added to a file that
was already open. `scenes/world.gd` is now past 17k lines, and the readouts
below are a coherent group with no dependency on `World` at all -- they take
numbers and strings and return text and colours. They live in
`src/ui/hud_readouts.gd`, tested by `tests/unit/test_hud_readouts.gd`, beside
`UiTheme`. The existing four stay where they are; this is where new ones go.

#### The phase of the day is the sun's elevation, not the clock

The strip already printed `Sun elev 41.3°`, a number with no meaning at the
player's chair. The same number, named, is the thing the player actually wants
to know -- whether it is about to get dark.

`HudReadouts.day_phase(sun_elevation_degrees, local_hour)` uses the real civil
twilight boundary rather than clock hours, because the clock hour of sunset
moves by months and by latitude while the elevation does not:

| Sun elevation | Phase |
|---------------|-------|
| `>= 6°` | **Day** |
| `-6°` to `6°`, before local noon | **Dawn** |
| `-6°` to `6°`, at or after local noon | **Dusk** |
| `< -6°` | **Night** |

The rising/setting split is `local_hour < 12` -- the game's local hour is local
*solar* time (it is derived from longitude, see `WorldCoordinates`), so solar
noon is 12 by construction, not by approximation.

### Condition chips: the bars finally say what is wrong

`SurvivalMeters` has carried eight named states since it was written --
`is_hungry`, `is_starving`, `is_thirsty`, `is_dehydrated`, `is_exhausted`,
`is_cold`, `is_freezing`, `is_malnourished` -- and the HUD showed exactly one
of them, as the warmth row's label. A player watching the food bar drop had no
way to know that 0.5 is where hunger starts costing them and 0.85 is where it
starts killing them; the bar is a fraction, and a fraction is not a warning.

`HudReadouts.condition_chips(meters, in_water)` returns the states that are
true right now as `{text, color}` entries, drawn as a row of small themed cards
directly above the survival panel, bottom-left -- with the bars they name, not
in some other corner.

Two rules, both pinned by test:

1. **Severity is the colour, and the colour is the theme's own good/bad pair.**
   A state that is actively taking the player apart is `UiTheme.NEGATIVE`; a
   state that is a warning is `UiTheme.ACCENT`; a state that is merely a fact
   about where the player is standing is `UiTheme.TEXT_MUTED`. No third palette.
2. **Severe first, then warnings, then facts, each tier in a fixed order.** The
   same reasoning as the message stack's fixed order: a chip must not move
   under the player's eye because an unrelated one appeared. Within a tier the
   order is food, water, warmth, rest, nutrition, place.

A severe chip **replaces** its own warning rather than stacking with it --
"Starving" and "Hungry" are the same meter, and showing both would double-count
one problem:

| Condition | Chip | Tier |
|-----------|------|------|
| `is_starving()` | **Starving** | severe |
| `is_hungry()` and not starving | **Hungry** | warning |
| `is_dehydrated()` | **Parched** | severe |
| `is_thirsty()` and not dehydrated | **Thirsty** | warning |
| `is_freezing()` | **Freezing** | severe |
| `is_cold()` and not freezing | **Cold** | warning |
| `is_exhausted()` | **Exhausted** | warning |
| `is_malnourished()` | **Malnourished** | warning |
| in water | **Swimming** | fact |

Nothing wrong and dry ground underfoot shows **no chips at all** -- an empty
row, not a row of green "OK" badges. The HUD is quiet when there is nothing to
say, the same way an empty message banner hides its whole card.

### The held-item card: what is in hand, and how close it is to breaking

The hotbar shows five icons and a stack count. It does not name what is
equipped, and nothing anywhere in the HUD shows **wear** -- `ItemWear` has
graded every tool's condition since it was written, and the only way a player
learnt an axe was about to break was that it broke.

A small themed card sits directly above the hotbar, bottom-centre, showing the
equipped item's display name and its `ItemWear.condition_for` grade.
`HudReadouts.held_item_line(name, condition)` is the pure half: the name alone
when the item has no material to wear (a torch, a fish), `"Name · Condition"`
when it does, and an empty string when nothing is equipped -- which hides the
whole card, the same `_set_message_banner` rule the banners follow.

### Three columns, and why every card sizes itself

Pillar 4 is the one thing in this doc that was *learned* rather than designed.
The first pass gave each new card a pinned top **and** bottom offset, the way
every HUD element in this file already had one — `WORLD_CLOCK_CARD_TOP = 178`,
`KARMA_CARD_TOP = 274`, and so on down every edge of the screen. Rendered at
the largest UI scale (`tools/probe_hud_layout.gd`) that produced:

- the world-clock card's third line clipping straight through the Karma card
  below it,
- the diagnostics strip's third line running off the bottom of the screen,
- the four survival meter rows overrunning each other, because each row was
  pinned to `SURVIVAL_BAR_HEIGHT` while the label centred in it had grown,
- the survival bars floating 150px wide inside a 390px card, because a
  `VBoxContainer` stretches every child to its widest one and the condition
  chips above them were wider.

Which is the same failure the message banners had, in a new place: two
elements agreeing to stay out of each other's way via constants that were only
ever correct for one font size.

Every HUD card is now a child of one of three `VBoxContainer` columns, built
by `World._build_hud_columns` before any card:

| Column | Anchored | Holds, top to bottom |
|--------|----------|----------------------|
| Left | top-left | player card (health + XP), land-sense card, creature panels |
| Right | top-right, under the minimap (`HUD_RIGHT_COLUMN_TOP`) | world clock, Karma |
| Bottom-left | bottom-left, growing up | condition chips, survival panel |

Three rules hold it together, each pinned by a render rather than by a
constant:

1. **A column never pins the edge its cards grow toward.** The left column
   pins its top, the bottom-left column its bottom, the right column its top
   and right. Nothing pins a height.
2. **A card is added with `_add_hud_card`**, which gives it
   `SIZE_SHRINK_BEGIN` (or `SIZE_SHRINK_END` in the right column) so it sizes
   to its own content and hugs its column's screen edge instead of being
   stretched to the widest card beside it.
3. **Anything whose height depends on a font size derives it.**
   `_survival_row_height()` is `max(SURVIVAL_BAR_HEIGHT, font_size(10, scale) + 4)`
   — at the default scale that is exactly `SURVIVAL_BAR_HEIGHT`, so the bars
   are unchanged, and above it the row grows with its label. A bar, its fill
   and its label are laid out by `_stretch_in_row`, so their height follows
   the row's and `_update_survival_bar`'s own `fill.size.x = …` keeps working
   untouched.

The player health bar is one of those rows: it is authored in `world.tscn`,
moved into the player card by `_build_xp_bar`, and then treated exactly like
the four meters below it — same row height, same label size, registered for
the same scale change. **`_stretch_in_row` writes anchors *and* offsets by
hand rather than calling `set_anchors_preset(PRESET_LEFT_WIDE)`**, and that
is not a style choice: the preset changes anchors and leaves offsets alone,
which is harmless on a node built at (0, 0) in code and not at all harmless
on a `.tscn`-authored one. The health bar's authored `offset_bottom = 14`
then read as *parent height plus 14*, drawing the bar 14px taller than the
row it was laid out in, straight through the XP label below it. Visible in
the render; invisible to every test in the suite.

The two floaters outside the columns are the held-item card (centred above the
hotbar) and the diagnostics strip (bottom-right); both grow away from the edge
they are anchored to, for the same reason.

The death card stays centred on the screen and is the one card in the HUD
allowed to sit over the world's middle, because it is the one message the
player must not miss.

### The minimap is framed like every other card

Asked for directly: *"add a border and borderradius of 4px to the minimap"*.

The minimap was the one readout on screen with no frame at all — a bare
`TextureRect` whose generated map ran to a hard square edge against the world
behind it, sitting directly above a world-clock card and a Karma card that
both have the shared rounded, bordered one. It is not a pillar-1 legibility
problem (a map is opaque; it does not vanish over snow), it is a *coherence*
one: the corner reads as one column only if everything in it is built the
same way.

`UiTheme.map_frame_stylebox()` is the frame: the shared `PANEL_BORDER` at the
shared `BORDER_WIDTH`, a **transparent** background — the map is the
background — and `MAP_CORNER_RADIUS` of **4**, the radius that was asked for
rather than the theme's own 6. Four is deliberate and pinned: a map is read
for the shapes in it, and the more its corners are rounded the more of the
actual map they eat.

Rounding a `TextureRect`'s own corners needs more than a stylebox, which
draws *behind* the texture rather than clipping it. Two nodes do it:

1. a **clipper** `Panel` with the same 4px-radius shape and
   `clip_children = CLIP_CHILDREN_ONLY`, so it is never drawn itself and its
   shape is used as a mask for the map inside it;
2. a **frame** `Panel` drawn *after* the map (later sibling = later draw, the
   rule this file's own "One CanvasLayer" section already states), carrying
   the border only.

The border has to be a separate node drawn on top rather than part of the
clipper, because a stylebox's border is drawn under the clipper's children —
the map would cover the inner half of it.

### The planner toggle is a switch, because it has two states

Asked for directly: *"make the planner switch a ios like switch button with
two states"*.

It was a `Button` whose caption was the mode you would switch **to** —
`ViewMode.toggle_label`, reading "Planner Mode" while you are in RPG mode and
"RPG Mode" while you are in planner mode. That is a correct label for a
*button*, and the wrong model for a *switch*: a button says what pressing it
does, a switch shows what is currently true. Both readings of "Planner Mode"
are available to a player looking at the old button — *am I in planner mode,
or is that what I get if I press it?* — and nothing on screen answered it.

A switch answers it by construction, so the label stops changing:

- The caption is the constant `ViewMode.SWITCH_LABEL` ("Planner"), naming the
  thing the switch controls rather than the action.
- The switch's **on** state is `ViewMode.shows_palette(mode)` — the existing
  predicate, not a second one that could drift from it.

`src/ui/toggle_switch.gd` is the widget, with its geometry and colours as
pure statics so the parts that can be wrong are tested rather than eyeballed:

| Rule | Why |
|------|-----|
| The knob is fully inside the track at **both** ends | A knob that overhangs at one end is the classic off-by-a-padding bug, and it only shows in one of the two states |
| Off→on moves the knob by exactly `track_width - knob - 2·padding` | The two rest positions are symmetric; neither end is special |
| The track is a pill: corner radius is **half its height** | What makes it read as a switch rather than a small rounded button |
| On is `UiTheme.ACCENT`, off is `UiTheme.BUTTON_NORMAL` | The theme's own existing on/off pair, not a third palette |
| On and off must be **visibly** different in luminance | A switch whose two states look alike is not a switch |

The knob slides rather than jumps — a short `Tween` on its position — which
is the whole reason an iOS switch reads as one control with two states
instead of two different pictures. The animation is deliberately *not*
tested: what is pinned is where the knob comes to rest.

Keyboard focus stays off it (`FOCUS_NONE`), for the reason the old button
already documented: a focused `Control` answers `ui_accept`, which is Space,
which is the attack key.

### UI scale

Every font size in the HUD was a hardcoded `add_theme_font_size_override`
between 9 and 28, chosen against one developer's monitor. `src/ui/ui_scale.gd`
is the settings model, the same shape `AudioSettings` and `SimulationSettings`
already have: a float multiplier, `sanitize`d into `[MIN_SCALE, MAX_SCALE]`
with NaN falling back to `DEFAULT_SCALE` (1.0, exactly today's look), driven by
a Settings > Interface slider and persisted in the `[ui]` section of the shared
settings file.

`UiScale.font_size(base, scale)` is how a size is applied, and it is the only
way one is: `maxi(MIN_FONT_SIZE, roundi(base * scale))`, so a tiny scale can
never round a 9pt label to 0 and make it vanish. It feeds two places:

- `UiTheme.build_theme(scale)` scales the theme's own default/Button/Label
  sizes, which covers every widget that does not override its size.
- Widgets that *do* override -- they are the ones this pass touched -- register
  their base size with `World._scaled_font(label, base)`, which applies the
  size now and re-applies it when the slider moves, so a scale change takes
  effect without a restart.

Deliberately **not** done by scaling the `$UI` CanvasLayer: a `CanvasLayer`
scales about its origin, so every bottom- and right-anchored card would walk
off the screen. Layout stays at one scale and text is what grows.

### The settlement card: what the place you are standing in is doing

Asked for directly: *"a context dependent Village / City panel which shows
stats and status of the village / city like population; happiness; gold and
so"*.

**Context-dependent means it appears because you are somewhere, not because
you pressed something.** A settlement exists per chunk
(`EntityRef.for_settlement`), so the card shows while the player stands in
a chunk that has one and hides the moment they leave — the same shape the
land-sense label and the creature panels already use, and the reason it
needs no key of its own.

**The title is the settlement's real tier, not the word "village".**
`SettlementTier.tier_for` already classifies a settlement as **hamlet /
town / city** from three real dimensions that must ALL cross together —
household count, active institutions, and production diversity — precisely
so that population alone never promotes a place. The card says whichever
one the simulation currently computes, so watching the title change from
Hamlet to Town is watching three real things happen at once.

**Every row is a read of state that already exists.** Nothing here is
tracked for the card's benefit:

| row | where it comes from |
|---|---|
| tier | `SettlementTier.tier_for` |
| population | households in the settlement, and how many are housed (`VillageCensus`) |
| happiness | `HouseholdWellbeing.mean_productivity`, the same number `settlement_productivity` already scales build rates by |
| worst need | the lowest of `HouseholdWellbeing`'s five real needs — food, shelter, work, income, community |
| gold | the settlement's own guild chest (`guild_for_settlement`) |
| food | village market stock against `FOOD_STOCK_PER_HOUSEHOLD_TARGET` |
| building | what the growth ladder says this settlement owes itself next |

**Happiness is shown with the reason beside it.** One blended percentage
is nearly useless on its own — `HouseholdWellbeing` is a weighted mix of
five needs, and "68%" tells a player nothing about what to do. Naming the
weakest need next to it ("68% · worst: food") turns the card from a score
into a prompt, and costs nothing, because the per-need numbers are already
computed to produce the blend.

**A settlement with no data reads as unknown, never as zero.** A chunk
whose village is loaded but whose households have not been assessed yet is
a real state, and showing 0% happiness for it would be a lie the player
would act on.

### FPS is back on, outside the diagnostics strip

FPS shipped in the middle of the clock line until the split-strip pass
moved it, with lat/lon and sun elevation, into the F3 diagnostics strip —
off by default. Reported back simply: *"also add back the FPS"*.

It returns to the always-on world-clock card, and **only it**: lat/lon and
sun elevation stay behind F3. Those two are genuinely diagnostic — a
player reads them when debugging worldgen — while a frame counter is
something you want visible while the thing it measures is going wrong,
which is exactly when you are not thinking to press F3.

## Status

- ✅ **The settlement card** (`src/ui/settlement_readout.gd`, 17 tests) —
  pure model, thin Node: facts in, strings out, so a city's rows are
  testable without founding one. `EarthChunkManager.settlement_readout_at`
  is the gatherer, returning `{}` where there is no settlement, which is
  the whole of "context dependent". Verified with a real render at both
  ends (`tools/probe_hud_layout.gd`): filled as a city in `busy`, and
  **gone rather than blank** in `calm`.
- ✅ Happiness is the households' mean **happiness**, not their mean
  **productivity**. `HouseholdWellbeing` keeps the two apart on purpose —
  productivity is happiness dragged down by hunger, because a household
  with a beautiful town and an empty stomach does not work well — so a row
  labelled happiness that reported the work rate would answer a different
  question than it asks.
- ✅ Food reads as **carrying capacity** (`SettlementFood.carrying_capacity`,
  "feeds 17 of 12"), the number the simulation already assesses a
  settlement by, rather than a raw stock figure invented for this card.
- ✅ **FPS is back on the always-on clock card**, sharing the movement line
  so the card's fixed three-line height is unchanged. `UNKNOWN_FPS` (0)
  leaves the reading off entirely on the first frame, before anything has
  been measured, rather than claiming 0.
- ⬜ **FPS now appears twice while F3 is open** — once on the clock card and
  once in the diagnostics strip. Harmless, and left alone deliberately:
  removing it from the strip would shrink `DIAGNOSTICS_LINE_COUNT` and
  rewrite a contract this request never asked about.
- ⬜ The card is read-only. It reports what a settlement is doing and offers
  no way to act on it — no way to see WHICH household is unhoused, or to
  act on the worst need it names.
- ⬜ Nothing is shown for a settlement whose chunk is not loaded, because
  the purse and the village market are only reachable while it is. A
  player cannot check on a town from the next valley.



- ✅ **One shared message stack** — `World._build_message_stack` /
  `_make_message_banner` / `_set_message_banner`; order pinned by
  `message_banner_lines`, tested (`test_world_hud.gd`).
- ✅ **World hints yield to gameplay windows** —
  `World.world_hint_visible_for`, consulted by `_update_interaction_prompt`,
  `_update_hover_tooltip` and the message stack, tested
  (`test_world_hud.gd`).
- ✅ **Meters read as reserves** — `World.reserve_for_deficit` /
  `meter_label_text`, tested (`test_world_hud.gd`), including the pin that the
  label and the fill agree at every deficit.
- ✅ **Karma readout, on the shared themed card** (2026-09-06, asked
  directly — see `docs/concept/karma_and_luck.md`) —
  `World._build_karma_display`/`_update_karma_display`, a `PanelContainer`
  (`UiTheme.panel_stylebox` via `_ui_theme`, pillar 1) just under the
  minimap, top-right. `World.karma_display_text`/`karma_display_color`
  are the pure, tested halves (`test_world_hud.gd`): a signed number,
  coloured gold/red/neutral by sign.
- ✅ **One shared mark for "this one is selected"** (2026-09-20) —
  `UiTheme.selected_button_stylebox` / `BUTTON_SELECTED`, pinned by
  `test_ui_theme.gd` against the measured failure it replaced: the
  distance from normal must beat the ~5% of value that `pressed` gave and
  that could not be seen. Its first consumer is the build palette's armed
  slot and open tab (see
  [planner_mode.md](planner_mode.md)'s "The build palette").
- ✅ **The top-left strip is split** — `$UI/DebugLabel` is gone from
  `world.tscn`. Its player half is the world-clock card
  (`World._build_world_clock_card`, `HudReadouts.world_clock_lines` /
  `day_phase`); its developer half is the bottom-right diagnostics strip
  (`_build_diagnostics_strip`, `HudReadouts.diagnostics_lines`), hidden until
  `toggle_diagnostics` (F3, `Keybindings`) and **not even written** while
  hidden. Tested (`test_hud_readouts.gd`, `test_keybindings.gd`).
- ✅ **Condition chips** — `HudReadouts.condition_chips` /
  `World._update_condition_chips`: a row of themed cards above the survival
  panel naming the `SurvivalMeters` states the bars only imply. Rebuilt only
  when `HudReadouts.chips_signature` changes, and the chip Labels are
  deliberately kept OUT of the UI-scale registry (they are freed and rebuilt
  as the player's state changes; a dictionary keyed by them would grow all
  session). Tested (`test_hud_readouts.gd`).
- ✅ **Held-item card** — `HudReadouts.held_item_line` /
  `World._update_held_item_card`, above the hotbar: what is equipped and its
  `ItemWear.condition_for` grade. Hides the card, not the label. Tested
  (`test_hud_readouts.gd`).
- ✅ **UI scale** — `src/ui/ui_scale.gd`, `UiTheme.build_theme(scale)` /
  `apply_scale`, a Settings > Interface slider
  (`SettingsOverlay._build_interface_section`), persisted by
  `World._save_ui_settings` in `[ui]`, applied by `_apply_ui_scale` without a
  restart. Tested (`test_ui_scale.gd`, `test_ui_theme.gd`,
  `test_settings_overlay_interface.gd`).
- ✅ **Pillar 1 finished** — the land-sense readout, the death label, the XP
  label, the health bar and the charge meter are all on the shared card;
  `UiTheme.compact_panel_stylebox` is the slim variant for the bar-shaped ones
  (tested). Each hides its **card**, never just its label.
- ✅ **World hints yield, charge meter included** — `_update_charge_meter`
  goes through `world_hint_visible_for`; it was the last world-space floater
  not covered by it.
- ✅ **Cards size themselves and stack in columns** (pillar 4) —
  `World._build_hud_columns` / `_add_hud_card` / `_survival_row_height`.
  Verified by rendering rather than by argument, at 0.75, 1.0 and 1.75
  (`tools/probe_hud_layout.gd`).
- ✅ **The minimap is framed** (2026-09-20, asked for directly) —
  `UiTheme.map_frame_stylebox`/`map_clip_stylebox` +
  `World._build_minimap_frame`: a clipper that rounds the map texture's own
  corners to 4px and a frame drawn over it carrying the shared border.
  Tested (`test_ui_theme.gd`) and rendered.
- ✅ **The planner toggle is a switch** (2026-09-20, asked for directly) —
  `src/ui/toggle_switch.gd`, captioned by the constant `ViewMode.SWITCH_LABEL`
  and turned on by the existing `ViewMode.shows_palette`. Geometry and colours
  tested (`test_toggle_switch.gd`), both states rendered. The render caught
  what the geometry tests could not: inside a row the track stretched and
  stopped being a pill, now pinned by
  `test_the_switch_keeps_its_own_height_inside_a_row`.
- 🚧 **Not verified in a live session.** Every check above is headless: unit
  tests plus offscreen renders of the real builders. Nobody has yet pressed
  F3, dragged the scale slider or watched a chip appear in a running game.

## Testing boundary

`World`'s own node wiring — which builder runs in `_ready()`, which node a
member points at — is untested glue over tested pieces, the same boundary
[persistence.md](persistence.md) already draws for the persistence wiring.
What is tested is the pure decisions: the banner order, the visibility rule
and the meter vocabulary in `tests/unit/test_world_hud.gd`; the readout text,
the day phase, the condition chips and the held-item line in
`tests/unit/test_hud_readouts.gd`; the scale model in
`tests/unit/test_ui_scale.gd`; the theme's cards in
`tests/unit/test_ui_theme.gd`; the Interface slider in
`tests/unit/test_settings_overlay_interface.gd`.

**Layout is the exception, and it is verified by rendering.**
`tools/probe_hud_layout.gd` calls World's own builders — not a mock-up that
can drift from them — reparents the real `$UI` CanvasLayer into a SubViewport
of the design size, fills every card with plausible mid-game content and saves
a PNG. It runs under `xvfb-run` with `--rendering-driver opengl3`; World is
instantiated but never added to the tree, so its `_ready` (license gate, chunk
manager, the ~52s of art warming) never runs. Run it at `0.75`, `1.0` and
`1.75` and look at the three images. Every layout bug listed under "Three
columns" above was found that way and by no other means — a unit test cannot
see a card clipping through the one below it.
