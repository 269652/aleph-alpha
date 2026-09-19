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
2. **A number and the bar beside it always mean the same thing, and full is
   always good.** Every meter is shown as a **reserve**, never as a deficit,
   whichever way the model happens to store it internally.
3. **The world's own hints never cover a window the player opened.** A prompt
   about the world *behind* a modal is noise even where it does not overlap.

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

- **The world-clock card**, top-left on the shared `UiTheme.panel_stylebox()`:
  the time, the phase of the day, the season, the weather, and how the player
  is moving. Always visible. `HudReadouts.world_clock_lines` is the pinned
  pure half.
- **The diagnostics strip**: FPS, latitude/longitude, sun elevation in degrees.
  **Hidden by default**, toggled with the rebindable `toggle_diagnostics`
  action (default **F3**). `HudReadouts.diagnostics_lines` is its pure half.

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

## Status

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
- ⬜ **The top-left strip is split** — the world-clock card always on, the
  diagnostics strip behind `toggle_diagnostics` (F3) and off by default.
  `HudReadouts.world_clock_lines` / `diagnostics_lines` / `day_phase`.
- ⬜ **Condition chips** — `HudReadouts.condition_chips`, a row of themed
  cards above the survival panel naming the `SurvivalMeters` states the bars
  only imply.
- ⬜ **Held-item card** — `HudReadouts.held_item_line`, above the hotbar:
  what is equipped and how close it is to breaking.
- ⬜ **UI scale** — `src/ui/ui_scale.gd` + `UiTheme.build_theme(scale)` +
  a Settings > Interface slider, persisted in `[ui]`.
- ⬜ **Pillar 1 finished** — the land-sense readout, the death label, the XP
  label and the charge meter move onto the shared card.
- ⬜ **The charge meter is world-space and not yet covered by
  `world_hint_visible_for`.** It is drawn above the player's own head, so it
  can overlap a window the same way the prompt did.

## Testing boundary

`World`'s own node wiring — which builder runs in `_ready()`, which node a
member points at — is untested glue over tested pieces, the same boundary
[persistence.md](persistence.md) already draws for the persistence wiring.
What is tested is the pure decisions: the banner order, the visibility rule
and the meter vocabulary in `tests/unit/test_world_hud.gd`; the readout text,
the day phase, the condition chips and the held-item line in
`tests/unit/test_hud_readouts.gd`; the scale model in
`tests/unit/test_ui_scale.gd`.
