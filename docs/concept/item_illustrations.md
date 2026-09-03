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
| **Icon** | Inventory grid, hotbar, paperdoll equip slots, drag-preview, tooltip | Eventually, per item — but see `sprite_id` below; nothing blocks on this today. Full catalog scaffolded into 11 generation-ready kits in [ai_sprite_prompts.md §9](../art/ai_sprite_prompts.md#9-general-item-icons--one-kit-per-visual-archetype-2026-08-28). |
| **Ground** | Dropped-item sprite | No — reuse the icon, scaled via `art_resolution.gd`'s `world_scale_for`. Already the convention (`dropped_item.gd`); keep it that way rather than authoring separate ground art. |
| **In-hand** | The equipped weapon/tool riding `ToolSlot` | No — reuse the icon. The rig is front-canonical only (no side/back art yet), so a distinct held-pose asset isn't worth authoring. |
| **Placed** | A `"placeable"`-kind item built into the world (`campfire`/`furnace`/`sagewerk`/`storage`) | **Yes — a second surface, distinct from Icon.** This table never named it until now — see "Placed structures" below. |
| **Use/swing motion** | Melee swing, rod-cast, lasso/net throw | **Deferred** — see below. |
| **Attack/cast effect** | What appears at the target when a hit or a spell atom resolves | Owned by [magic.md](magic.md), not this doc — see below. |
| **Rarity/variant** | Any of the above | Not decided in this pass — see Open questions. |

### Done: items have a real `sprite_id`

`Item` (`item.gd`) used to have no icon/texture field at all — every surface
re-derived a picture purely from the item's own `id` string at draw time, via
`ProceduralItemSprite`'s color+silhouette lookup table
(`generate_texture(item_id)`/`texture_for(item_id)`). One id reliably meant
one texture, but only because identity and art were never allowed to
diverge.

`Item` now has `sprite_id: String` (see `docs/progress.md`'s Items section).
It defaults to the item's own `id` whenever nothing sets it explicitly, so
every catalog entry still renders exactly as before with zero authoring
changes — `ItemCatalog._ITEMS` doesn't set a divergent `sprite_id` for any
entry yet, so this is real, live groundwork rather than a visible change on
its own. Every caller that used to key art off `item.id` directly (inventory
grid, hotbar, paperdoll, drag-preview, dropped-item, the armor slots below)
now goes through `item.sprite_id` instead.

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

### Done: armor is visible on the rig

`Equipment.SLOTS` (`equipment.gd`) is `["head", "chest", "legs", "feet",
"weapon"]`, but `CharacterView` (`scenes/character_view.gd` /
`character_view.tscn`) used to only have real slot nodes for `HeadSlot` and
`ToolSlot` — `_slot_node()` returned `null` for `"chest"`/`"legs"`/`"feet"`,
and `Player.equip_armor()`/`unequip_slot()` never called `_character_view` at
all, so worn armor was purely numeric (`Equipment.total_armor()`) everywhere,
in-world and in the inventory paperdoll preview alike. This was the
equip-slot half of the open question `character_art_brief.md`'s
"Decorations" section had flagged ("equippable cosmetic items beyond the
existing `HeadSlot`/`ToolSlot`?") — armor is that answer, and it shipped.

What shipped (see `docs/progress.md`'s Items section, "The equipment
paperdoll is the real CharacterView rig"):

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

Honest scope (per `docs/progress.md`): slot positions are a reasoned
starting placement, not yet visually confirmed against real armor art in a
live screenshot.

### Placed structures: a second surface this doc never named

Every row in the states table above is about a HELD or CARRIED picture —
icon, ground, in-hand — all deliberately converging on one texture per item.
A placeable (`campfire`/`furnace`/`sagewerk`/`storage`, `item.kind ==
"placeable"`) already breaks that convergence today, silently:
`ProceduralItemSprite` draws its inventory icon (`_draw_campfire`/
`_draw_furnace`, or the generic flat-plate fallback for `sagewerk`/`storage`
— see [ai_sprite_prompts.md §9g](../art/ai_sprite_prompts.md#9g-placeable-structures--campfire-furnace-sagewerk-storage)),
while `ProceduralStructureSprite` (`src/rendering/procedural_structure_sprite.gd`)
independently draws what the SAME item looks like once built — baked
straight into `TerrainRenderer`'s own tile atlas (`STRUCTURE_IDS`,
`terrain_renderer.gd:184-191,522-538,925,1033-1085`) rather than drawn as a
`Sprite2D` the way every other surface above is. Two generators, two
unrelated pictures, one item id, and no row above ever named the second one.

This matters for illustrated art specifically because `ProceduralStructureSprite`
already takes a seeded `variant_seed` per structure
(`_campfire_image`/`_furnace_image`/`_sagewerk_image`/`_storage_image`,
`procedural_structure_sprite.gd:97,184,267,338`) — the same "many looks, one
id, picked by seed" shape `boulders.png`/ore already use, not the
`boar_walk.png` action-strip shape. A real illustrated upgrade for placed
structures is therefore a variant GRID, not an animation cycle.

### Sheet spec: placed structures get a seeded-variant grid, not a strip

A third instance of a pattern this codebase already has twice, not a new
one — mirrors `IllustratedStoneSprite`/`IllustratedTerrainSprite`'s existing
`has_variants()`/`frame_for()` shape exactly (`illustrated_stone_sprite.gd:164`,
`illustrated_terrain_sprite.gd:176`):

- **One sheet per structure id** — `campfire.png`, `furnace.png`,
  `sagewerk.png`, `storage.png` under a new `assets/sprites/structures/`
  folder. No existing folder fits: `assets/sprites/` root is walk-cycle
  species, `terrain/` is biome ground tiles, neither is a placed structure.
- **Grid, not strip, isolated objects, not full-bleed tiles** — the ore
  precedent's padded, cropped-to-content 5×5 grid
  ([ai_sprite_prompts.md §5](../art/ai_sprite_prompts.md#5-ore-nodes--one-sheet-per-ore-type-boulder-scale-with-embedded-deposits)),
  not terrain's full-bleed-square tiling convention — a placed structure has
  real empty ground around it in-world, it does not need to tile
  edge-to-edge against a copy of itself. Fall back to §3's 3×3 grid only if
  5×5 genuinely doesn't hold for a boxier architectural silhouette; try 5×5
  first rather than pre-committing to the smaller grid.
- **Selection stays seeded, not resampled per redraw** — a new
  `frame_for(structure_id, seed)` picks one variant deterministically per
  placed instance, mirroring `IllustratedStoneSprite.frame_for`/
  `IllustratedTerrainSprite.frame_for` exactly: a given campfire keeps the
  same illustrated look for its whole lifetime.
- **Wiring seam** — a new `IllustratedStructureSprite`
  (`src/rendering/illustrated_structure_sprite.gd`), and `TerrainRenderer`
  gains a `has_variants(structure_id)`-gated preference for it ahead of
  `ProceduralStructureSprite`, the same layering `StoneRenderer`/
  `TerrainRenderer` already apply for stone and biome tiles
  (`stone_renderer.gd:266,326`, `terrain_renderer.gd:848`). **Not built in
  this pass** — per this project's TDD rule, a meaningful test needs real
  source pixels to slice and measure against, the same reason
  `IllustratedCharacterSprite._PARTS` stays empty until hair/beard art
  exists (`character_art_brief.md`'s own Status table). Generation prompts
  are ready now ([ai_sprite_prompts.md §10](../art/ai_sprite_prompts.md#10-placed-structures--seeded-variant-grids-2026-09-03));
  wiring is the follow-up once real art lands.

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
