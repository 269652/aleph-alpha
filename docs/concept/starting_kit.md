# Starting Kit

A new character's gear is the player's own choice: 3 items picked from a
curated early-game pool, in the character creator's own Starting Kit tab —
not named "Bestiary"-style ("starter") loosely, deliberately: `docs/progress.md`
already uses "Starter Collection"/"choose your starter" for an unrelated,
*rejected* handheld-creature Easter egg (a fixed wolf companion shipped
instead), so this doc and its module are named precisely to read as a
different feature in a future grep.

## Status

Built. Replaces what used to be a hardcoded, identical-for-everyone kit
granted in `Player._ready()` (Iron Sword equipped, Iron Axe, Leather Helm,
Leather Chest, Fishing Rod).

## Design pillars

1. **The kit is the player's choice, not the class's.** [classes.md](classes.md)
   already frames archetype as a stat/skill lens, never a restriction —
   gear is the one thing that was previously identical regardless of class,
   and now it's the one thing that's entirely class-independent player
   choice instead. Every class sees the same pool.
2. **Curated, not comprehensive.** The pool is deliberately smaller than
   "every early-game item" — see Pool below for what was cut and why. A
   choice between 8 meaningfully different options beats a choice between
   12 where several are redundant or non-functional.
3. **Always a valid default.** A player who never opens the tab still
   starts a real, coherent kit — mirrors the character tab's own
   `_selected_class` defaulting to `"warrior"` rather than blocking Begin
   until the player acts. No new "disabled button" UI machinery exists in
   the creator anywhere; this doesn't invent the first one.
4. **One data source, reused.** The pool is real `ItemCatalog` ids; granting
   a choice reuses the exact `has()` → `make()` → `inventory.add()` pattern
   the dev console's `/give` command already established
   (`World._handle_give_command`). No parallel item-description or
   starter-specific data lives anywhere except the pool list itself and its
   UI blurbs (`StarterKit`, `MainMenu.STARTER_ITEM_BLURBS`).

## Pool

`wooden_club`, `crude_blade`, `stone_pickaxe`, `fishing_rod`, `lasso`,
`rough_compass`, `iron_sword`, `iron_axe` (`src/gameplay/starter_kit.gd`).

Three distinct early paths are represented at least once each: combat
(wooden_club/crude_blade/iron_sword), mining (stone_pickaxe), fishing
(fishing_rod), taming (lasso), wayfinding (rough_compass) — plus the two
iron-tier items as the "invest more now" option in combat/utility.

**Cut from the original candidate list, deliberately:**

- **Torch** — `kind: "material"`, and `HotbarAction`'s kind→action map has
  no `"material"` entry. A torch cannot be equipped, used, or placed today
  — it would be a strictly dead pick until it has a real interactive loop
  (a light-radius mechanic, most likely — not spec'd anywhere yet).
- **Snare / Trap / Butterfly Net** — each is mechanically necessary for its
  own narrow capture class ([taming.md](taming.md)'s capture-class table),
  but giving all three equal pool-weight next to Lasso (viable against
  nearly everything) skewed an earlier 12-item pool a third of the way
  toward one system a brand-new player hasn't even scoped out yet. Lasso
  alone represents "taming" in the pool; the other three stay fully
  craftable once discovered.

## Recipes

Iron Sword and Iron Axe previously had **no recipe anywhere** in
`crafting_recipe_book.gd` — reachable only via `/give`, the shop, or the old
hardcoded kit grant. Including them in a pool the player actually crafts
their way back into (after spending one, or on a second character) meant
giving both a real one:

```
iron_sword: 2x iron_ingot + 1x stick -> 1x iron_sword
iron_axe:   2x iron_ingot + 1x stick -> 1x iron_axe
```

Costed like the armor pieces just above them in the book (2 ingots sits at
`iron_helm`'s own scale) plus a stick for the hilt/haft, the same "hafted
tool needs a stick" shape `stone_pickaxe`/`crude_blade`/`fishing_rod`/
`rough_compass` already use. No `requires_structure` — matching every other
iron-tier recipe in this book; shaping an already-smelted ingot needs no
further gate anywhere else, so these don't invent one either.

## Mechanism

- `StarterKit` (`src/gameplay/starter_kit.gd`) — pure data, mirrors
  `class_archetype.gd`'s shape exactly: the pool, `MAX_CHOICES := 3`, a
  `DEFAULT_CHOICES` (crude_blade + stone_pickaxe + fishing_rod — a weapon,
  a mining tool, and specifically the same item the old fixed kit granted
  for the exact same "discover fishing" reason), and `is_valid_choice()`.
  No blurb/UI text — that lives in `MainMenu.STARTER_ITEM_BLURBS`, the same
  split `CLASS_BLURBS` already uses for classes.
- `MainMenu`'s Starting Kit tab (between Character and Skills — Skills is
  an explicit no-commitment preview, this is a real committed choice like
  class itself) — one card per pool item, mirroring the class picker's own
  icon-card shape exactly, just multi-select up to `MAX_CHOICES` instead of
  single-select. Clicking a selected card deselects it; clicking an
  unselected card while already at 3 is a no-op (simplest predictable
  rule — no replace-oldest logic).
- `Player.grant_starter_items(item_ids)` — called by `World` once, right
  after the fresh player node enters the tree (so `inventory_changed`'s
  hotbar-sync connection, wired in `_ready()`, is already live). Auto-equips
  the first weapon-kind choice; if none was chosen, the first tool-kind
  choice instead (`equip_item` already accepts either kind) — so a
  `{pickaxe, compass, lasso}` pick starts holding the pickaxe, not
  bare-handed just because nothing is literally a weapon. Bare-handed only
  when neither kind was chosen at all: a real, intended consequence of
  replacing the old kit outright.
- The load-game path (`apply_save_dict`) is untouched — a loaded
  character's inventory has always come from the save file, never from
  `_ready()`'s grant.

## Non-goals (for now)

- No re-roll/refund of a spent starting choice — picking a kit is a
  one-time creation-time decision, like the class itself.
- No per-class pool differences. Every archetype sees the identical 8.
- No rendering of a torch's light radius, or any other fix to why Torch was
  cut — that's real, separate scope, not attempted here.
