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

### Spells as items

Resolves the open question from [magic.md](magic.md): yes — a designed
spell can be crystallized into a tradeable item (scroll/gem/rune), socketed
or consumed to grant a spell to a character that didn't design it. A spell
gem's own rarity is derived from the complexity/rarity of the atoms used to
build it, plugging spellcrafting directly into the same item-rarity
vocabulary as everything else, and giving the crafting/trading economy
(see [economy.md](economy.md)) a genuinely novel tradeable category no
other system here produces.

### Open questions

- Full affix pool and how it's segmented per item category (weapon vs
  armor vs tool vs spell gem).
- Equipment slots / build-around-gear depth — how much itemization should
  matter relative to skill-web/DNA-driven power, so gear augments a build
  instead of overriding it.
