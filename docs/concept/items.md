## Items

A PoE-ish rarity/affix system is the shared vocabulary for "how interesting
is this item" — common → rare → legendary, the same tier language
[dna.md](dna.md) already uses for creature genetics, kept consistent across
systems on purpose.

Two complementary sources feed that shared vocabulary rather than
competing:

- **Found/looted gear** rolls rarity and affixes randomly, classic
  Diablo/PoE loot-drop excitement — the thing you might get lucky on.
- **Crafted gear** is deterministic via [crafting.md](crafting.md)'s
  blueprint DSL — no luck involved, but bounded by which base templates/
  modifiers your skill and materials give you access to. The incentive to
  craft over loot-farm: guaranteed, targetable affixes instead of a random
  chance at them.

Both tracks land in the same rarity tiers and the same underlying stat/
affix pool, so a legendary found sword and a legendary crafted sword are
comparable, just arrived at differently.

What *names* an item once it is assembled by the player rather than picked
from an authored table is specified separately in
[item_identity.md](item_identity.md): an emergent item's id is a content hash
of its canonical structure, which is what lets a crafted item survive a save
at all.

How two items of the same material in the same shape can still be a file and a
spring is specified in [heat_treatment.md](heat_treatment.md): quench, temper
and sharpen slide one material along a single hardness/toughness curve that no
draw is allowed to cheat.

What an item actually *looks like* — in the inventory, on the ground, in
hand, worn as armor, or built into the world as a placeable — is specified
separately in [item_illustrations.md](item_illustrations.md): a real
`sprite_id` on `Item`, real worn-armor visuals on the character rig, and a
second seeded-variant sheet for placed structures, all reusing the same
composite-spritemap engine the hero and named creatures already use.
Spell/atom attack effects are that doc's sibling concern, specified in
[magic.md](magic.md#atom-effects-render-as-composite-spritemaps-one-per-atom-2026-08-28).

### Reading an item

Hovering an item in the inventory is how the player learns what it is. The
tooltip is built in a fixed order, and **every line after the first two is
conditional**:

1. **Name** — the item's display name.
2. **Kind** — Weapon / Tool / Armor / Food / Potion / Placeable / Material.
3. **Material**, in words — e.g. `Iron — hard, keen`.
4. **Weight** — kilograms.
5. **Damage** — for a weapon.
6. **Armor**, with the slot it protects — e.g. `Armor: 4 (Chest)`.
7. **Freshness** and **shelf life** — food only.
8. **Stack** — `Stack: 3 / 5` for anything stackable.

Two rules govern that list.

**A stat that is not modelled is omitted, never printed as zero.** `item.gd`'s
convention is that `0.0` means "nobody has modelled this yet", so a tooltip
showing `0.00 kg` would be stating a measurement the game has never made.
Raw meat therefore shows name/kind/stack and nothing else; an iron sword shows
its real 1.20 kg. Concretely, real weight exists today only for the three
weapon-kind items (whose material + volume estimate is recorded in
`ItemCatalog._WEAPON_MATERIAL_AND_VOLUME`) plus carrot and potato — widening
that table is a known follow-up, and until it happens most tooltips honestly
carry no weight or material line at all.

**The numbers shown are derived, not authored.** Weight is literally
`MaterialProperties.mass_kg_for(material, volume_cm3)` — real density × real
volume, per [materials.md](materials.md)'s momentum model — so the tooltip is
showing the material model's own output rather than a per-recipe number
somebody typed in.

#### Material: descriptors, not a spreadsheet

The material line names the material and then **describes it in words**
(`hard`, `keen`, `brittle`, `buoyant`), never as the property vector's raw
scalars. This follows [materials.md](materials.md)'s "Learning an emergent
system" section directly: the default is descriptors + discovery, and a deeper
inspect surfacing raw numbers for min-maxers stays a possible later affordance
rather than the default hover text.

Each descriptor's threshold is a named, calibration-tested constant on
`MaterialProperties`, and **three** of the four reuse cutoffs the game had
already fixed elsewhere — `brittle` is the same toughness line the impact model
fractures at, `buoyant` the same water-density line raft viability uses, and as
of 2026-08-28 `hard` is the same line the impact model refuses to let a point
pierce (`ImpactResolver.PIERCE_HARDNESS_CAP`), so *a point cannot pierce
anything the tooltip calls hard* — so a word in a tooltip and a behaviour in
the simulation cannot come to mean different things.

`hard` itself moved that day, from stone's hardness to **iron's**, when
`materials.md`'s hardness column became published Vickers: on a real
indentation scale rock is seven times harder than wrought iron, so keeping
stone as the cutoff would have dropped iron out of the word and broken the
`Iron — hard, keen` line this page documents. Every material's *word* is
unchanged; only the number behind it is now a measurement. There is deliberately no "heavy" descriptor: an item's mass
is already shown as a real number, and a vaguer word for it would be a
downgrade.

#### Food: freshness and shelf life

Food really does go off in your pack. A food tooltip shows its current
soundness as a percentage and how long that food keeps **in the season the
player is currently standing in** — e.g. `Keeps 1.8 days in summer` for a
cherry versus `Keeps 24.0 days in summer` for a walnut, and 120 days for the
same walnut in winter. Both come from the real per-item keeping multiplier and
seasonal factor in `FruitSpoilage`; the 66× spread between soft fruit and a
nut in its shell is the whole reason to cache nuts and eat cherries first, and
it was previously invisible.

Both lines are season-dependent by construction, so a caller that does not
know the season supplies none and both lines are omitted — the same
"say nothing rather than guess" rule as the unmodelled stats above.

### Spells as items

Resolves the open question from [magic.md](magic.md): yes — a designed
spell can be crystallized into a tradeable item, socketed or consumed to
grant a spell to a character that didn't design it. Two distinct vessels,
not one (see magic.md's 2026-08-24 brainstorm for the full mechanism):

- **Spell gems** — sealed, use-only. Grants on-item casting *charges*
  without teaching the recipe; no skill/atom requirement to use one.
- **Spell scrolls** — teachable. Reading one attempts to permanently learn
  the spell, gated by the same skill/atom requirements authoring it would
  need; consumed only on a successful learn.

Both derive their rarity/value from the same complexity score
(`rarity_tier.tier_from_complexity`), which is also what magic.md's
exponential-in-LOC gold crafting cost is derived from — plugging
spellcrafting directly into the same item-rarity vocabulary as everything
else, and giving the crafting/trading economy (see [economy.md](economy.md))
a genuinely novel tradeable category no other system here produces.

### Open questions

- Full affix pool and how it's segmented per item category (weapon vs
  armor vs tool vs spell gem).
- Equipment slots / build-around-gear depth — how much itemization should
  matter relative to skill-web/DNA-driven power, so gear augments a build
  instead of overriding it.
