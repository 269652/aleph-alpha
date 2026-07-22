# Smelting & Metalworking

The bridge from raw mined **ore** to worked **metal gear**. This is the concrete
first rung of [materials.md](materials.md)'s mineral track ("metal, stone, ore")
and slots into [crafting.md](crafting.md) as a heat-gated recipe category: the
tech step that lifts the player out of the stone-and-bone tier into iron tools,
weapons, and armor.

## Design pillars

1. **Ore is not usable raw — it must be smelted.** Real metallurgy: ore + a
   reducing **fuel** (charcoal/coal) + sustained **heat** yields metal. Mining
   gives you `iron_ore`/`copper_ore`; you can't wear or wield those — you smelt
   them into `iron_ingot`/`copper_ingot` first. This makes fuel and a heat
   source genuinely valuable, and gives coal a purpose beyond a black rock.
2. **Heat-gated, like cooking.** Smelting requires a heat source present (a
   campfire, or the sturdier crafted **furnace**), exactly as
   [cooking](cooking.md) requires a fire — one consistent "you need warmth to
   transform this" rule across the crafting surface (`CampfireCooking` and
   `Smelting` share the gate shape).
3. **Deterministic recipes now, emergent material physics later.** Smelting is a
   fixed ore→ingot lookup and ingots→gear recipes today (test-pinned, no RNG).
   This is the compiling-toward-`materials.md` note made concrete: eventually an
   ingot carries the mineral property vector and the gear's stats *emerge* from
   shape+assembly; for now iron simply beats stone/leather by fixed numbers.

## The chain

1. **Mine** ore-bearing boulders with a pickaxe → `iron_ore` / `copper_ore` /
   `coal` (already implemented, see the Mining rows in progress.md).
2. **Build a furnace** (crafted from `stone`) — the dedicated, better heat
   source; a carried campfire also works as a low-tier smelter.
3. **Smelt**: `iron_ore` + `coal` (fuel) at a heat source → `iron_ingot`;
   `copper_ore` + `coal` → `copper_ingot`. Consumes the ore and the fuel.
4. **Forge**: ingots are the inputs for the metal tier — `iron_helm`/
   `iron_chest`/`iron_legs`/`iron_boots` (armor that clearly out-protects
   leather) and better weapons/tools. These are ordinary heat-gated crafting
   recipes.

## Status / mechanisms

- ✅ Smelting transform (ore + coal + heat → ingot) — `src/gameplay/smelting.gd`
  (tested); `Player.craft` heat-gates smelting recipes on a carried campfire or
  furnace. Ingot recipes live in `crafting_recipe_book.gd`, shown in the crafting UI.
- ✅ `iron_ingot` / `copper_ingot` items + the crafted **furnace** heat source +
  a full **iron armor set** (helm/chest/legs/boots), all with their own pixel art.
- ✅ Iron armor out-protects leather (2× armor values, feeds `Equipment.total_armor`).
- ⬜ Charcoal from wood (a renewable fuel besides mined coal).
- ⬜ Material-property-vector emergence (the `materials.md` target: stats fall out
  of composite material + shape rather than fixed per-recipe numbers).
- ⬜ Smithing skill quality multiplier (a master realizes more of an item's
  ceiling — see `materials.md`).
