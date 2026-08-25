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
- 🚧 **The rest of the HUD is not audited against pillar 1.** The land-sense
  readout (`_land_sense_label`), the death label, the XP label and the charge
  meter are still bare `Label`s/`ColorRect`s without the shared card. The
  land-sense and XP ones sit in screen corners rather than over open terrain,
  which is why they were not swept in with the message banners — but they are
  not *specified* as exempt, they are simply untouched.
- ⬜ **No in-world UI scale / font-size setting.** Every size above is a
  hardcoded `font_size` override.
- ⬜ **The charge meter is world-space and not yet covered by
  `world_hint_visible_for`.** It is drawn above the player's own head, so it
  can overlap a window the same way the prompt did.

## Testing boundary

`World`'s own node wiring — which builder runs in `_ready()`, which node a
member points at — is untested glue over tested pieces, the same boundary
[persistence.md](persistence.md) already draws for the persistence wiring.
What is tested is the pure decisions: the banner order, the visibility rule
and the meter vocabulary, all in `tests/unit/test_world_hud.gd`.
