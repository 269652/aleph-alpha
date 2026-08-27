# Labor Skills (Use-Based Mastery)

A second, separate progression axis alongside [skills.md](skills.md)'s PoE-style
passive web. That web stays exactly as designed — combat/magic **build power**,
spent from level-up skill points, for Warriors/Mages/Rangers/Beastmasters. This
doc covers something orthogonal: **practical mastery that grows from doing the
thing**, not from allocating points. Fell a hundred trees, get measurably better
at felling trees. Forge a hundred swords, forge better swords. No point to spend,
no menu to open — the skill itself levels from use, exactly like the PoE web
levels from combat/quest XP, just on its own per-skill track.

Both axes matter to the same character: a Warrior's PoE web makes them hit
harder; their (entirely separate) Smithing skill determines how good the sword
they forge actually is. A pure crafter can dump every level-up point into
defensive web nodes and still become the server's best smith purely through
reps — the two systems don't gate each other.

## Design pillars

1. **Practice, not points.** A skill's level is a pure function of accumulated,
   value-weighted experience in that skill's own actions — there is nothing to
   allocate and nothing to respec. This is the entire mechanical distinction
   from [skills.md](skills.md)'s web, not a variant of it.
2. **One shared mechanism for players and NPCs.** A village blacksmith who has
   been forging for years is mechanically just an NPC running the identical
   `Skill` code the player does, fed by their own occupation-production loop
   (see [npc.md](npc.md)) instead of manual player action. This is what makes
   "buy from a highly-skilled crafter" a real economic choice instead of flavor
   text, and it's what makes the stated late-game goal possible: a player who
   commits real hours to a trade plays far more reps against their own skill
   than an NPC's occupation loop passively accrues, and can specifically grind
   the one skill an NPC only practices incidentally — so a dedicated player
   naturally outpaces any single NPC given enough time.
3. **Skill sets the ceiling, materials and recipe reach for it.** Restates
   [materials.md](materials.md#the-crafting-act-character--player-skill)'s
   own framing: *"a master smith realizes more of an item's theoretical
   potential from the same parts."* High skill alone doesn't guarantee a great
   item — a Grandmaster smith forging from scrap iron still gets a mediocre
   sword. Skill, material quality (ore purity, DNA-driven organic rarity —
   already designed), and the [crafting.md](crafting.md) blueprint combination
   all multiply together; none of them alone caps the outcome.
4. **No eyeballed constants.** Every curve here (XP-to-level, tier thresholds,
   the ceiling-realization multiplier) is a pure, test-pinned function, the
   same discipline `ExperienceTrack` already established for the PoE web's own
   leveling (see [progression.md](progression.md)) and required project-wide
   by this repo's own process rules.
5. **No failure state.** A novice woodcutter still fells the tree — just
   slower, for a smaller yield, from a lower-quality cut. Low skill is a
   penalty to the outcome, never a dice roll that can whiff entirely. This
   matches [crafting.md](crafting.md)'s own "deterministic, no random roll on
   craft" philosophy extended honestly to the one input that used to feel
   stochastic (whether you're "good" at something) — now it's legibly just
   reps.

## The skill roster

Every skill maps to an action that already exists or is already designed —
this list is grounded, not aspirational padding:

| Skill | Actions | Feeds |
|---|---|---|
| Woodcutting | Felling trees (`choppable_tree.gd`) | Lumber yield/speed |
| Mining | Breaking stone/ore (`smashable_stone.gd`, `minable_ore.gd`) | Ore yield/speed, rare-vein odds |
| Fishing | Catching fish ([fishing.md](fishing.md)) | Catch yield/speed, rare-catch odds |
| Foraging | Gathering wild plants ([seed_dispersal.md](seed_dispersal.md), wild crops) | Gather yield/speed |
| Farming | Planting/tending crops ([farming.md](farming.md)) | Crop yield/quality |
| Herbalism | Gathering/using medicinal plants (the Herbalist archetype's practical trade) | Potency, [cooking.md](cooking.md) buff-food quality |
| Cooking | Preparing food ([cooking.md](cooking.md)) | Buff magnitude/duration |
| Smithing | Smelting ore, forging weapons/armor ([smelting.md](smelting.md), [crafting.md](crafting.md)) | Ceiling-realization on crafted gear (see below) |
| Construction | Building structures ([building.md](building.md), [housing.md](housing.md)) | Build speed, structure durability |
| Animal Handling | Taming/bonding creatures ([taming.md](taming.md), [pets.md](pets.md)) | Taming odds, bond-rate |

Deliberately **excludes** combat sub-skills (swordsmanship, archery, spell
schools) — that power already lives in the PoE web per this session's
clarification. Adding a new labor skill later (e.g. Alchemy, once
potion-brewing exists) costs one roster entry, not new plumbing: every skill
is the same shared `Skill` resource, not bespoke per-skill code.

## Mechanism

### `Skill` (shared, reused by every entry above and by NPCs)

Mirrors `ExperienceTrack`'s existing shape (`current_xp`, `level`, pure
add-XP/level-up logic), but **independent per skill and per actor** — chopping
trees never grants Mining XP, and the player's Smithing level is entirely
separate from any NPC's.

- **Value-weighted XP, not flat-per-action.** Reuses
  [progression.md](progression.md#ecological-literacy-xp-from-reading-the-world-not-just-fighting-it)'s
  own precedent (XP scaled by genuinely reading the simulation, not the raw
  act) applied generally: felling a rare hardwood grants more Woodcutting XP
  than a common softwood; smelting a rare ore grants more Smithing XP than
  common iron. A tested, monotonic function of the action's own real
  difficulty/rarity, not a hand-picked table.
- **Diminishing XP for trivial repetition at high skill**, relative to the
  action's own difficulty — a max-level woodcutter chopping seedling saplings
  stops being an efficient grind path. Pure function of `(skill_level,
  action_difficulty)`, tested, not a hand-tuned cliff.

### Tiers

Named thresholds (Novice → Apprentice → Journeyman → Expert → Master →
Grandmaster) — a tested step function of `level`, not a spendable resource.
Crossing a tier unlocks a **passive** bonus automatically, universally, for
every action that skill covers:

- **Gathering skills** (Woodcutting/Mining/Fishing/Foraging/Farming): yield
  and speed bonuses per tier.
- **Production skills** (Smithing/Cooking/Construction): the
  ceiling-realization multiplier below, plus access to higher-tier blueprint
  modifier slots — this is what actually answers
  [crafting.md](crafting.md#open-questions)'s open "how station tiers gate
  blueprint complexity" question: the **station** gates what's *possible*
  (a village forge can't hold a legendary-tier blueprint slot no matter who's
  swinging the hammer); the **crafter's tier** gates how *well* whatever the
  station allows gets realized. Both gates, doing different jobs.

### Skill-driven crafting quality (closes smelting.md's open TODO)

Directly answers
[smelting.md](smelting.md#open-questions)'s *"⬜ Smithing skill quality
multiplier (a master realizes more of an item's ceiling — see materials.md)"*
and [materials.md](materials.md#the-crafting-act-character--player-skill)'s
own framing above, as one small multiplicative hook rather than a rework of
the already-designed blueprint DSL:

```
final_item_stat = base_stat_from_blueprint_dsl(base + materials + modifiers)
                 * ceiling_realization(crafter_skill_level)
```

`ceiling_realization` is a tested, monotonic curve from a real floor (a true
Novice still produces a usable, if middling, item — never worthless) up to
**exactly 1.0 at Grandmaster**, not an asymptote that never quite arrives:
true mastery is achievable, matching the blueprint DSL's own "fully
deterministic, no random roll" honesty — skill was the one input that used to
feel like luck; this makes it legibly just accumulated reps. A Grandmaster
smith with perfect materials and the ideal blueprint combination gets the
item's actual, full theoretical stats, every time.

**NPCs run the identical formula against their own skill level**, grown by
[npc.md](npc.md)'s existing occupation-production loop (each automatic
production tick accrues that NPC's own Smithing/Farming/etc. XP exactly as a
player's manual action would) rather than any separate NPC-only stat. A
settlement's blacksmith has a real, inspectable skill level that has
genuinely grown over in-game time, not a flavor number.

## The auction house

Not a new system bolted on — a natural extension of the already-built
per-settlement `Market` (`src/emergence/market.gd`, Phase 5 of the emergence
economy, done). A listing carries the **crafter's identity and skill tier**
alongside the item, not just an `item_id`: two "iron sword" listings from a
Journeyman and a Grandmaster are genuinely different items with different
stats (per the formula above), priced on top of the Market's existing
supply/demand curve by a quality premium.

- **Single-player-viable from day one.** Browsing a settlement's market
  already surfaces goods from NPC crafters of varying, growing skill —
  including a chance to buy a better weapon than the player can currently
  forge themselves, from a settlement's own master smith. This delivers the
  "buy your way to good gear" fantasy immediately, without waiting on
  multiplayer.
- **Forward-compatible with real multiplayer** (`roadmap.md` Phase 5+): a
  listing's seller is either an NPC id or a player id — the market/pricing
  code doesn't need to know or care which, so this needs no redesign once
  real players can list goods. Directly the mechanism
  [economy.md](economy.md)'s own *"Selling to the market (NPC and, later,
  player)"* line was already gesturing at.
- **The stated late-game payoff falls out for free**: once a player commits
  real hours to Smithing specifically, they out-level any single NPC's
  incidental occupation-loop practice (pillar 2 above) — so the best gear on
  a server's market increasingly comes from a dedicated player crafter, not
  the village blacksmith, which is exactly the goal stated for this design.

## Status

⬜ Everything below is pure design — nothing in this doc is implemented yet.

- ⬜ Shared `Skill` resource (XP/level/tier, pure + tested, mirrors
  `ExperienceTrack`).
- ⬜ Per-action XP hooks across the ten roster skills.
- ⬜ Tier-unlocked passive bonuses (gathering yield/speed, production
  ceiling-realization).
- ⬜ `ceiling_realization` multiplier wired into the blueprint DSL's item-stat
  calculation.
- ⬜ NPCs accruing their own skill XP from `occupation_production.gd`'s
  existing automatic recipe loop.
- ⬜ Auction house UI/listing extension on `src/emergence/market.gd`.

## Open questions

- Exact tier thresholds and per-tier bonus magnitudes — needs a real tuning
  pass once a first skill (Smithing, given the explicit ask driving this doc)
  is prototyped, not decided from first principles.
- No skill decay from disuse is the recommended default (matches this
  design's generally forgiving tone elsewhere — free respec, no punishing
  RNG) but isn't a final decision.
- **Two parallel NPC-economy implementations currently exist**: the older,
  food-only `npc_economy.gd`/`village_market.gd` (live-wired, simple fixed
  markup) and the newer, general-goods `src/emergence/market.gd`
  (supply/demand pricing, reuses `CraftingRecipeBook`). This doc assumes NPC
  skill-driven production feeds the newer emergence market, since it already
  handles arbitrary goods — the older system may need folding into it or
  retiring; a decision for whoever picks that up, not blocking this design.
- Full roster completeness — new labor skills should stay cheap to add as new
  gatherable/craftable systems land (e.g. a future Alchemy skill once
  potion-brewing exists); the ten above are a first pass, not a ceiling.
