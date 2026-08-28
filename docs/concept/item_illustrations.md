## Item illustrations: one composite-spritemap engine, every state

Items get the same treatment [character_art_brief.md](character_art_brief.md)
and `illustrated_animal_sprite.gd` already proved out for the hero and for
named creatures: a fixed-canvas, chroma-keyed composite spritemap per subject,
procedural art as the always-available fallback underneath it. This doc does
not invent a second art pipeline — it points items at the existing one and
says which states it needs to cover.

### States an item's art must cover

| State | Surfaces | New art needed? |
|---|---|---|
| **Icon** | Inventory grid, hotbar, paperdoll equip slots, drag-preview, tooltip | Eventually, per item — but see `sprite_id` below; nothing blocks on this today. |
| **Ground** | Dropped-item sprite | No — reuse the icon, scaled via `art_resolution.gd`'s `world_scale_for`. Already the convention (`dropped_item.gd`); keep it that way rather than authoring separate ground art. |
| **In-hand** | The equipped weapon/tool riding `ToolSlot` | No — reuse the icon. The rig is front-canonical only (no side/back art yet), so a distinct held-pose asset isn't worth authoring. |
| **Use/swing motion** | Melee swing, rod-cast, lasso/net throw | **Deferred** — see below. |
| **Attack/cast effect** | What appears at the target when a hit or a spell atom resolves | Owned by [magic.md](magic.md), not this doc — see below. |
| **Rarity/variant** | Any of the above | Not decided in this pass — see Open questions. |

### Decision: items get a real `sprite_id`

Today `Item` (`item.gd`) has no icon/texture field at all — every surface
above re-derives a picture purely from the item's own `id` string at draw
time, via `ProceduralItemSprite`'s color+silhouette lookup table
(`generate_texture(item_id)`/`texture_for(item_id)`). One id reliably means
one texture, but only because identity and art have never been allowed to
diverge.

`Item` gains `sprite_id: String`. `ItemCatalog.make()` defaults it to the
item's own `id` whenever the catalog doesn't specify one, so every existing
entry keeps rendering exactly as it does today with zero authoring changes.
Every caller that currently keys art off `item.id` (inventory grid, hotbar,
paperdoll, drag-preview, dropped-item, the new armor slots below) switches to
`item.sprite_id` instead.

What this buys: an item id and its art can now diverge on purpose. A crafted
or "blessed" variant of a base item can share its art via `sprite_id` without
duplicating a catalog art entry, and swapping an item onto real illustrated
art later (per `docs/concept/art_resolution.md`'s still-pending Phase 6) only
ever means editing the catalog's `sprite_id`, never touching a renderer.

Not resolved here: `carrot`/`potato` already have real illustrated ground art
(`IllustratedCropSprite`) that the inventory/hotbar path doesn't use, so those
two items show different pictures depending on where they're rendered. A
`sprite_id`-aware icon path could close that, but doing so isn't committed as
part of this pass.

### Decision: armor becomes visible on the rig

Today `Equipment.SLOTS` (`equipment.gd`) is `["head", "chest", "legs", "feet",
"weapon"]`, but `CharacterView` (`scenes/character_view.gd` /
`character_view.tscn`) only has real slot nodes for `HeadSlot` and
`ToolSlot` — `_slot_node()` returns `null` for `"chest"`/`"legs"`/`"feet"`,
and `Player.equip_armor()`/`unequip_slot()` never call `_character_view` at
all. Worn armor is therefore purely numeric (`Equipment.total_armor()`)
everywhere today, in-world and in the inventory paperdoll preview alike. This
is the equip-slot half of the open question `character_art_brief.md`'s
"Decorations" section already flagged ("equippable cosmetic items beyond the
existing `HeadSlot`/`ToolSlot`?") — armor is that answer.

The fix:

- Three new `Sprite2D` slot nodes — `ChestSlot`, `LegsSlot`, `FeetSlot` —
  alongside the existing `HeadSlot`/`ToolSlot`, and `_slot_node()` extended to
  match them.
- `Player.equip_armor()`/`unequip_slot()` call `_character_view` the same way
  `equip_item()` already does for weapons, so equipping a helm/chest/legs/
  boots piece actually changes what the rig (and the paperdoll preview, which
  is its own `CharacterView` instance) shows.
- Real art, not the old placeholder. `equip_slot(slot_name, color)` is a
  flat-color fill — always a scaffold (its own neighbor `equip_weapon`'s doc
  comment calls it out by name as "the flat-color placeholder"), unit-tested
  but with no production caller today. Armor should follow `equip_weapon`'s
  actual precedent instead: the item's own generated icon texture (via
  `sprite_id` above), the same picture already shown for that item
  everywhere else — not a second, disconnected flat-color system.
- Z-order follows the rule the rig already applies (`character_view.gd`'s own
  comments: `Body` before `Arms` "so a hand always paints in front of the
  torso's sleeve fabric"; `ToolSlot` last "so a held weapon draws over
  everything"). `ChestSlot` sits right after `Body` (still behind `Arms`);
  `LegsSlot`/`FeetSlot` sit right after `LegLeft`/`LegRight` (still behind
  `Body`). Exact offsets get measured against the real generated textures at
  implementation time, the same way every other part's scale/offset already
  is — nothing here is eyeballed.

### Deferred: per-item use/swing art

Out of scope for this pass. `WeaponSwing`/`ToolSlot`'s existing procedural
rotation (a 60°-either-side pendulum over 0.2s) stays the swing for every
weapon and tool, mundane or magical, including a spell cast — see magic.md
below — and the new armor slots don't swing at all. Real per-frame swing art
(matching the boss-ability grid convention in
`docs/art/ai_sprite_prompts.md` §6) is a plausible later upgrade for
signature/legendary weapons specifically, not the whole catalog, and isn't
needed to ship `sprite_id` or armor visuals.

### Attack effects live in magic.md, not here

Per-atom composite spritemaps for spell effects are specified in
[magic.md](magic.md#atom-effects-render-as-composite-spritemaps-one-per-atom-2026-08-28),
not duplicated here. Items and atoms share the same underlying illustrated-
sprite engine (`illustrated_animal_sprite.gd`'s proven canvas/chroma-key/
divider-line/action-fallback pattern), but an effect is keyed by atom id, not
item id — the effect belongs to the spell being cast, not to whichever wand
or weapon triggered it. Non-magical weapon attacks stay exactly as they are
today (procedural rotation, no impact sprite) unless the deferred swing-art
idea above is picked back up.

### Open questions

- Rarity-driven tinting/glow: `rarity_tier.gd` already computes a real
  `tier_color()`, but nothing renders it — the only rarity-colored items
  today (`rare_fish`/`legendary_fish`) are two hardcoded
  `ProceduralItemSprite` entries whose colors don't even match
  `rarity_tier.gd`'s own table. Wiring real rarity visuals onto the
  `sprite_id` pipeline above is a natural next step but wasn't decided here.
- Whether to unify the carrot/potato ground-vs-UI divergence onto
  `sprite_id` (see above) — not committed.
- Whether `sprite_id` should ever diverge from `id` for anything other than
  crafted/variant art reuse (e.g. a purely cosmetic reskin) is unexplored.
