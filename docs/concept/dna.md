Both; players and npc have a DNA which determines stats, traits, looks and other things. 

DNA and classes should resonate; so when a player creates a new character it will have a random DNA which resonates more or less with different classes. So there might be a DNA suitable to be played as Mage; another which fits better to a warrior and so on.

**Resolved: resonance is soft/efficiency-only, not a gate.** See
[classes.md](classes.md) — a resonance score per archetype (e.g. 72% Mage)
governs leveling speed/stat gains in that archetype, never which spells,
recipes, or skills a player can eventually reach. This keeps the reroll
mechanic below as the "optimize faster" lever without letting a bad DNA
roll lock anyone out of a playstyle.

There should be common, rare and legendary DNA traits which have a given chance to spawn. A player can reroll character generation a few times (3-5) then they need to buy premium credits to do more rolls if they are not happy with the dna for their char.

Children (see [players.md](players.md)) inherit DNA as a genetic cross of
both parents rather than a fresh independent roll, with a small mutation
chance for novel traits. [evolution.md](evolution.md)'s own "Bloodlines"
section specifies the same real crossover mechanism applied to tamed/bred
ANIMALS — reusing this exact inheritance shape, not a second one.

### Wild animals have DNA too, and the player selects on it

The same `DnaCrossover` now runs on animals nobody has tamed. A butterfly
carries one heritable trait — **boldness** — derived from its own world cell
when the meadow seeds it, and crossed from **both parents** when a courting
pair produces young (see
[ecosystem_dynamics.md](ecosystem_dynamics.md)'s "The butterfly that knows
you"). One crossover function, shared with players' children and with bred
livestock; no second implementation.

What that buys is not a stat: it is that **the player becomes a selection
pressure without anything being written to make them one**. Boldness decides
which butterflies come close and which flee, so who a player can catch is
decided by the same number their offspring inherit. Net the ones that come to
you and the shy ones are what is left to breed. Nothing in the code says "the
meadow gets shyer" — it is arithmetic, measured across ten generations in
`test_a_meadow_the_player_nets_the_bold_out_of_grows_shy_over_generations`
(mean boldness 0.496 → 0.377, against 0.019 of drift in the identical
untouched control).

Two honest limits, both named rather than left to be found:

- **Nothing nets a butterfly in the live game yet.** The net is craftable and
  `CaptureTool` knows what it is for, but no interaction removes an ambient
  flyer from the world. The pressure is real in the model and dormant in the
  running game.
- **Ambient flyers are not persisted.** A chunk's flyers are re-derived from
  their cells' seeds on load, so an evolved meadow reverts to its founding
  personalities when that chunk unloads. Boldness drifts within a session, not
  across one.

### Appearance: DNA is the base, cosmetics layer on top

DNA deterministically generates the underlying body/phenotype as described
above — that part stays non-negotiable, and rerolling DNA (or having a
child) is the only way to change it. On top of that fixed base, players get
an ordinary cosmetic customization layer that doesn't touch genetics:
hairstyle, dye/color, tattoos/markings, and gear/clothing appearance. Same
split most RPGs already draw between "body" and "style" — it keeps DNA
meaningful (you can't cosmetic your way to a different creature/build
fitness) while not condemning anyone to a phenotype-generated hair color
they hate forever.
