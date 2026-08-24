## Skills

A unique skill system inspired by Path of Exile's passive web, layered with
per-player DNA-driven uniqueness. This is **combat/magic build power**,
spent from level-up skill points — see [progression.md](progression.md) for
how those points are earned. It is deliberately separate from
[labor_skills.md](labor_skills.md)'s use-based practical mastery (Woodcutting,
Smithing, Farming, ...), which levels from doing the corresponding action, not
from allocation. A character advances both at once, independently.

### Per-archetype webs, softly gated

Each of the 7 [archetypes](classes.md) has mostly its own PoE-style passive
web (small stat nodes, occasional keystone-style major passives that
meaningfully change how a build plays). A player isn't walled out of other
archetypes' webs — they can path into them — but doing so costs more the
further it is from their [DNA resonance](dna.md), same efficiency-only
philosophy as class resonance itself: a high-Warrior/low-Mage character
*can* path deep into the Mage web, it's just slower going than for a
naturally resonant character. This keeps each web small and legible
individually (easier to design/balance for a solo dev) while preserving the
already-decided "no hard class lock" principle.

Webs connect outward into their domain's system: combat nodes feed
[combat.md](combat.md) stats, Mage nodes unlock [magic.md](magic.md) atoms
and raise their parameter caps, Artisan nodes unlock
[crafting.md](crafting.md) recipes, Beastmaster nodes improve
[pets.md](pets.md) taming/bonding, etc.

### DNA-driven uniqueness (two layers)

1. **One signature node per character.** Every player has exactly one
   procedurally-generated skill/spell, seeded from their DNA, that no other
   player has — a genuine "this is MY character" hook, not just a reskin.
   Generation is constrained by the same rules as any player-authored spell
   (see [magic.md](magic.md)'s cost-formula and physics constraints) so a
   signature skill can be flavorfully unique without being able to roll
   overpowered.
2. **DNA-flavored variants on some shared nodes.** A handful of shared web
   nodes (not all — most stay uniform for legibility) have DNA-gated
   variants: everyone can take the node, but your specific DNA changes its
   effect (e.g. a shared "Elemental Bolt" node fires as a piercing beam for
   one DNA flavor, a bouncing projectile for another, same underlying cost).

### Open questions

- Respec cost/mechanism — free, trainer-NPC-mediated for a fee (tying into
  [economy.md](economy.md)), or capped-per-day? Needs its own decision pass.
- How many keystone-tier major passives per archetype web is the right
  amount to keep builds distinctive without exploding balance surface area?
- Which shared nodes get DNA-flavored variants, and how many variants per
  node (2-3 fixed flavors vs. a wider procedural range)?
