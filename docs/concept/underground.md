# The underground

[geology.md](geology.md) specifies the *rock*: four real strata, what ore
concentrates in each, and the hazards of digging through them. This doc is
everything the rock *contains* -- the cave systems water carved into it, the
biosphere living down there, why it gets harder and richer the deeper you go,
and what "an instance" means on a planet that has exactly one copy of itself.

The surface is deliberately peaceful. Real animals live there and a few of
them are dangerous ([ecosystem_dynamics.md](ecosystem_dynamics.md)'s bears,
lions and venomous snakes), and every so often the population sim promotes an
exceptional individual into a [world boss](worldbosses.md) -- but there is no
monster population above ground, and there is not going to be one. **The
underground is where the threat lives**, and it earns that by being a
genuinely different place rather than the same place with the lights off.

## Design pillars

**1. Each layer changes the verb, not the numbers.** Difficulty does not come
from a depth multiplier on creature stats. It comes from each layer asking a
different question:

| layer | verb | what the layer is |
|---|---|---|
| topsoil / regolith | **dig** | there is no space until you make it |
| **bedrock** | **explore** | the space was already there; water made it |
| deep bedrock | **survive** | the space is trying to kill you (collapse, blackdamp, water) |
| hydrothermal | **exploit** | the space is *alive*, and it is not on your side |

This doc's main subject is the second one -- bedrock, the first layer where
the underground stops being a hole you dug and becomes a place that existed
before you arrived.

**2. The cave was already there.** A bedrock cave system is not level design
and not a room graph. It is the output of real speleogenesis: water with
dissolved CO2 works along joints and bedding planes in soluble rock over
geological time, and the *shape* it leaves behind is determined by how that
water got into the rock in the first place. Two regions with different
hydrology get genuinely different caves for the same reason two latitudes get
different biomes -- a real physical cause, computed, not authored. This is
[exploration.md](exploration.md)'s "no hand-placed puzzle rooms" pillar
applied to the geometry itself, not just to the obstacles in it.

**3. A second biosphere, not a monster list.** The underground food web does
not run on sunlight and is not descended from the surface one. It runs on
**chemosynthesis** -- chemical energy from oxidising reduced compounds that
the rock and its water supply -- which is a real, well-documented way for an
entire isolated ecosystem to exist with no connection to the sun. That single
decision is what makes the underground another world rather than a dark
version of this one, and it is where "monster" comes from: not a bestiary,
but a clade whose biochemistry is legitimately alien to everything the player
has met above ground.

**4. Depth is a trade, not a tier.** Reward rises with depth. So does cost --
haulage, light, air, water, and the real risk of not coming back. Real mining
formalises exactly this as **cutoff grade**: rock is "ore" only if its grade
clears what it costs to get it out, and that cost climbs with depth. A deeper
layer must therefore be a *decision*, not an upgrade that strictly dominates
the one above it. A player who mines the best cells and walks past the rest is
playing correctly, and that is what a real mine looks like.

**5. One planet, no copies.** There is no server-side duplicate of anything,
ever. See "Instancing without instances" below -- exclusivity is physical and
economic (a claim, a gate, a flooded passage), which is a real mechanism this
world can simulate, where a per-party copy is a piece of server bookkeeping
pretending to be a place.

## Real-world grounding

### Lithology: caves need the right rock

Nothing in this project currently knows what rock anything is made of --
[stone.md](stone.md) says so itself ("⬜ Stone type varying by biome ... today
all loose stone is the same grey granite"). That gap is load-bearing here,
because the single biggest control on whether a cave system can exist at all
is whether the bedrock dissolves.

Real continental lithology is not uniform, and its proportions are measured.
Carbonate rocks (limestone and dolomite) crop out over **15.2% of the global
ice-free continental surface** -- the figure from the World Karst Aquifer Map
(Goldscheider et al., 2020, *Hydrogeology Journal*), which is the modern
global survey of exactly this question. Evaporites (gypsum, anhydrite) are far
rarer but dissolve far faster, and produce real, large cave systems where they
occur -- Ukraine's Optymistychna, the longest gypsum cave in the world.
Crystalline basement (granite, gneiss) and clastic sediments (sandstone,
shale) make up most of the rest and are effectively insoluble.

`Lithology` therefore classifies bedrock into eight real rock types at
**province scale** (tens of kilometres -- real lithological provinces are
regional, not per-tile), weighted so the global carbonate share comes out at
that measured 15.2%, and biased by **relief**: real orogenic belts expose
crystalline basement and metamorphics, while low-relief platforms are
dominated by sedimentary cover. The game already has real elevation and real
slope ([terrain_relief.md](terrain_relief.md)), so that bias reads a signal
this world genuinely computes rather than an invented regional tag.

Dissolution rates are ordered by real chemistry, not by tier: gypsum dissolves
far faster than limestone, limestone faster than dolomite, and granite,
gneiss, sandstone and shale do not meaningfully dissolve at all. Insoluble
bedrock gets **no solutional cave system** -- which is the point. Most of the
planet has no cave under it, and the regions that do are a real, findable
minority with a real reason.

Basalt is the deliberate exception: it is insoluble, but real basalt flows
produce **lava tubes**, a genuine non-solutional cave type with a completely
different shape (long, linear, single-conduit, no branching). It is specced
here and listed as future work rather than quietly folded into the solutional
model, because folding it in would be a lie about how it forms.

### Palmer: how the water gets in decides what the cave looks like

The governing reference for solutional cave morphology is Arthur N. Palmer's
"Origin and morphology of limestone caves" (*GSA Bulletin* 103, 1991), whose
central finding is that cave pattern is controlled primarily by **the mode of
groundwater recharge** -- not by rock type, not by depth, not by age. Palmer's
survey of mapped caves found **branchwork patterns account for roughly 57%**
of solutional caves, with the various maze types making up most of the
remainder.

| recharge mode | real driver | pattern | reads as |
|---|---|---|---|
| **sinkhole** (point recharge) | a surface stream sinking into soluble rock | **branchwork** | dendritic tributaries joining downstream, like a river network in rock |
| **diffuse** | slow percolation through a permeable insoluble caprock | **network maze** | an angular grid of intersecting fissures on two joint sets |
| **floodwater** | episodic high-discharge injection from a sinking stream in flood | **anastomotic maze** | curvilinear braided loops, like a river's anabranches |
| **hypogenic** | acidic water rising from *below* (H2S oxidising to sulfuric acid) | **ramiform** | irregular rooms with branching side passages -- Carlsbad, Lechuguilla |
| **mixing zone** | fresh and salt water mixing near a coast | **spongework** | irregular interconnected cavities, no through-route |

Every one of those five drivers is a signal this game already simulates or can
derive: surface channels and their discharge ([hydrology.md](hydrology.md),
[rivers.md](rivers.md)), precipitation seasonality
([climate_dynamics.md](climate_dynamics.md), [seasons.md](seasons.md)),
distance to the coast, the overlying rock from `Lithology`, and proximity to
the hydrothermal layer `geology.md` already configures.

The hypogenic row is the one that ties the whole design together. Hypogenic
caves are dissolved **from below**, by rising sulfidic water -- and rising
sulfidic water is *also* the energy source the underground biosphere runs on
(next section). So in the deepest and most dangerous systems, the thing that
carved the cave and the thing that feeds what lives in it are the same thing.
That is not a designed coincidence; it is why Movile Cave and Frasassi are
both hypogenic caves and both chemosynthetic ecosystems.

### Chemosynthesis: the second biosphere

**Chemolithoautotrophy** is carbon fixation powered by oxidising inorganic
compounds -- hydrogen sulfide, hydrogen, ferrous iron, ammonium, methane --
instead of by light. It is the basis of several real ecosystems that are
completely independent of the sun:

- **Movile Cave, Romania.** Sealed off for roughly 5.5 million years. Around
  48 species, 33 of them found nowhere else, and the entire food web rests on
  floating microbial mats of sulfur-oxidising and methane-oxidising bacteria.
  This is the canonical proof that an isolated chemosynthetic *animal*
  community can exist underground, not just a bacterial film.
- **Frasassi caves, Italy** and **Cueva de Villa Luz, Mexico.** Sulfidic
  groundwater feeding **snottites** -- dangling biofilms of *Acidithiobacillus*
  that concentrate sulfuric acid to around **pH 0-1**, low enough to attack
  rock and equipment.
- **The deep subsurface.** *Candidatus* Desulforudis audaxviator was found
  about 2.8 km down in the Mponeng gold mine, South Africa, living on hydrogen
  produced by radiolysis of water -- effectively a single-species ecosystem,
  with no connection to the surface at all.
- **Hydrothermal vents.** Giant tube worms (*Riftia*), vent mussels
  (*Bathymodiolus*) and yeti crabs (*Kiwa*) are large animals in an
  energy-poor place because they host **endosymbiotic chemoautotrophs** --
  they farm their own producers internally. *Riftia* has no gut at all.

That last point is the single most important one for gameplay, and it gives
the difficulty curve a real mechanism instead of a multiplier:

- **Ambient chemical energy is scarce**, and falls off with distance from
  wherever reduced fluids actually rise. Scarce energy means **low population
  density** -- you meet *few* things down here, not swarms.
- **What you do meet is old.** Low metabolic rate, near-zero predation
  pressure and a physically constant environment produce extreme longevity:
  the olm (*Proteus anguinus*), Europe's blind cave salamander, lives past 100
  years. Age and accumulated traits are *precisely* the axis
  [worldbosses.md](worldbosses.md)'s promotion threshold already measures. A
  deep cave is therefore a statistical boss factory using the existing
  promotion mechanic, with no cave-specific boss code at all.
- **Symbionts break the energy ceiling.** An animal hosting its own producers
  is not limited by ambient flux, so it can be genuinely large somewhere that
  should not support anything large. That is what an apex is down here, and it
  is a real biological fact rather than a stat budget.

Put together: **few, old, and -- where symbiosis is involved -- enormous.**
Difficulty rises with depth because the energy model says it should.

### The four cave zones, and why the deep one is a refuge

Cave biology uses a real, standard zonation by distance from an entrance:
**entrance zone** (surface conditions, surface species), **twilight zone**
(light falling off, no photosynthesis), **transition zone** (dark, but surface
weather still reaches it), and **deep cave zone** (total darkness, ~100%
humidity, and temperature effectively constant at the region's mean annual
surface temperature).

That last property is worth as much as the ore. A deep cave is a real,
physically-justified refuge from surface weather and seasons -- which is why
people have stored food in caves for as long as there have been people and
caves. It connects straight into [survival.md](survival.md),
[seasons.md](seasons.md), [weather.md](weather.md) and
[cooking.md](cooking.md): the underground is not only somewhere to raid, it is
somewhere to *keep* things.

### Darkness is absolute, and that is a deliberate exception

[lighting.md](lighting.md)'s first pillar is "night is dim, never pitch
black," justified explicitly by moonlight, starlight and skyglow. Below the
twilight zone, none of those exist. The justification does not travel
underground, so the rule does not either: **the deep cave zone renders at true
black**, and a carried light is the only thing that makes it navigable. This
is a principled exception, not a contradiction -- it applies the same physical
reasoning `lighting.md` used, to a place where the physics gives the opposite
answer.

Real caving practice makes light a logistics problem rather than a toggle: the
standing safety rule is **three independent light sources per person**,
because a cave with no light is not "dark", it is a place you cannot leave.

### Cutoff grade: why deeper is not simply better

Real mining decides what counts as ore with a **cutoff grade** -- the mineral
concentration below which extraction does not pay. The cutoff is set by cost,
and cost rises with depth: longer haulage, forced ventilation, pumping to keep
water out, and ground support. `geology.md` already makes deeper rock richer
(`Strata.ORE_DENSITY_BY_LAYER` rises with depth) and more dangerous
(`GeologyHazards`). Cutoff grade is the missing third term that turns those
two into a real decision: a deep cell must be richer *by enough* to be worth
the trip, so a player rationally works the best cells and leaves the rest
standing.

## Mechanism

### Lithology (`src/world/lithology.gd`)

Province-scale deterministic rock classification. `rock_at(global_x, global_y,
relief)` returns one of `limestone`, `dolomite`, `gypsum`, `sandstone`,
`shale`, `granite`, `gneiss`, `basalt`, constant across a province-sized cell
(`PROVINCE_TILES`) so a cave system is not chopped up by per-tile noise.
`solubility_of(rock)` returns a real relative dissolution rate, with the four
insoluble types at exactly zero. The weight table is split into a low-relief
platform vector and a high-relief orogen vector, blended by relief, and pinned
by a test that samples across relief and asserts the resulting carbonate share
lands on the measured global 15.2%.

This is also the honest answer to `stone.md`'s open "stone type varying by
biome" item: the correct control is lithology, not biome -- limestone country
is limestone country regardless of whether forest or grassland is growing on
top of it.

### Recharge and pattern (`cave_recharge.gd`, `cave_pattern.gd`)

`CaveRecharge.mode_at(...)` derives which of Palmer's five recharge modes
applies from signals the world already has: a sinking surface channel, an
insoluble permeable caprock, precipitation seasonality, hydrothermal
proximity, and coastal distance. `CavePattern.pattern_for(rock, recharge)`
maps that to a Palmer pattern, and returns `PATTERN_NONE` for any insoluble
rock regardless of recharge -- no rock to dissolve, no cave. A test pins the
branchwork share against Palmer's own surveyed ~57%.

### The cave network (`cave_network.gd`) and `Strata.KIND_VOID`

`Strata` gains a fourth cell kind: **`VOID`**, a natural passage, distinct
from `TUNNEL` (a cell a player mined out). Both are walkable; the distinction
carries real meaning. A `VOID` was never mined, so nobody took ore out of it
and it can host the ecology. A `TUNNEL` is somebody's working, which is what
a claim is staked on.

`CaveNetwork` answers "is this cell a natural void" per pattern,
deterministically, with a per-pattern **porosity** (void fraction). Real caves
occupy a very small fraction of their host rock; network mazes are the densest
pattern and still nothing like open space. Branchwork is generated as a real
connected dendritic network rather than scattered cells, because a branchwork
cave that is not connected is not a branchwork cave.

### Descent: a pitch, not a staircase

Layers connect where the deeper layer's own void geometry reaches up to the
floor of the layer above -- a real **aven/pitch**, the way cave levels
actually connect. A descent point is therefore not scattered at random: it is
a place where two independently-generated void fields happen to open at the
same horizontal position, which means finding one is a genuine exploration
result rather than a spawned staircase.

Descending below the twilight zone requires a light source. This is a hard
gate, and it is the first real use `lighting.md`'s torch has that is not
cosmetic.

### Instancing without instances

The decision, taken explicitly: **there are no per-party copies, no fixed
dungeon layouts, and no lockout timers.** What players actually want from
instances -- repeatable content, and a place that is *theirs* -- is delivered
by two real mechanisms instead.

**Repeatability comes from the split between a finite resource and a renewable
place.** Ore is finite: `Strata.mine_at` is already permanent, and mined rock
does not come back. But a cave system is not only its ore. The chemosynthetic
mats regrow wherever the chemical flux continues, a drained sump refills,
speleothems keep growing (on a real, extremely slow timescale -- millimetres
per decade), and the fauna repopulate from the energy budget. A stripped cave
stays stripped in the way that matters and stays alive in the way that
matters. Beyond that, the renewable resource is *the planet*: a real world has
far more cave systems than any population of players will ever exhaust, and
`exploration.md`'s causal POI weighting decides where they are.

**Exclusivity comes from a real mining claim, not from a copy.** Real claim
law holds a working through discovery, marking, and -- critically -- *actually
working it*; a claim that is not worked lapses. In game: a player or guild
that timbers a working (`TunnelSupport` already exists and already models
real span-vs-collapse) and builds a gate at its mouth
([building.md](building.md)) holds that working, and loses it if they stop
working it. That is a place that is genuinely yours, that other players can
genuinely see, contest, and take -- which is strictly more interesting than a
private copy, and it hooks straight into
[player_citizenship.md](player_citizenship.md),
[governance.md](governance.md) and [factions.md](factions.md) instead of
sitting outside them.

**Why the alternatives were rejected.** A per-party copy asserts that the same
place exists several times, which contradicts the persistent-shared-world
pillar this project has held everywhere else, and it makes the world's
resources infinite in a game whose entire economy depends on them not being.
Fixed dungeon layouts contradict `exploration.md`'s explicit "no hand-placed
puzzle rooms, switches, or bespoke mechanisms exist anywhere". Lockout timers
are the respawn-timer pattern `world.md` already rejected for land health --
a bookkeeping clock standing in for a physical reason.

### What is down there (content)

The underground clade is defined the way the surface roster already is: by
**trophic role against the local energy budget**, with the existing creature /
DNA / evolution systems instantiating individuals -- not as a hand-authored
bestiary. The pools are keyed by **zone and chemical flux** rather than by
biome, which is the exact same shape as
`HERBIVORE_SPECIES_POOL_BY_BIOME`/`PREDATOR_SPECIES_POOL_BY_BIOME`, asking the
underground's own question.

- **Mat grazers** -- small, blind, depigmented, slow. Graze sulfur-oxidising
  microbial mats. Movile's isopods and springtails are the real analogue. The
  base of the animal food web and the commonest thing you meet.
- **Seep predators** -- concentrated near rising sulfidic fluid, where the
  ambient energy is high enough to support predation at all.
- **Symbiont-bearers** -- host their own chemoautotrophs, escape the ambient
  ceiling, and are the only things down here that get genuinely large. These
  are what `worldbosses.md`'s promotion threshold finds, because they are old
  *and* large *and* the environment let them stay that way.
- **Snottites** -- not a creature but a hazard: pH 0-1 biofilm that drips.
  Real, and a natural fit for [item_durability.md](item_durability.md), since
  what it attacks is equipment.

Non-creature content, all of it grounded:

- **Iron at real depth.** Already implemented (`GeologyOreGenesis` weights iron
  to bedrock/deep bedrock, from real banded iron formations). This is the
  actual tech gate into [smelting.md](smelting.md).
- **Saltpetre from cave earth.** Historically, niter for gunpowder was mined
  out of cave sediments -- and the nitrifying bacteria that make it are
  themselves chemolithoautotrophs, so it belongs to this doc's biosphere
  rather than sitting beside it. A real [eras.md](eras.md) progression gate.
- **Speleothems as climate archives.** Real stalagmites record paleoclimate in
  their banding, and this game *actually simulates* climate history
  ([climate_dynamics.md](climate_dynamics.md)). A readable speleothem is
  literally `exploration.md`'s "what happened here?" question with a real
  answer -- and a natural payoff for [progression.md](progression.md)'s
  Naturalist branch, which already exists to surface real simulation numbers.
- **Chemosynthetic biomass as food.** Food that does not depend on the surface
  at all, which means a cave can carry a settlement through a famine or a
  winter that the surface cannot. Real consequence for
  [survival.md](survival.md) and [economy.md](economy.md).
- **Constant temperature as cold storage.** See the zonation section.
- **Abandoned workings.** `docs/emergence/05`'s "abandoned infrastructure:
  mines" category, with the real causal `ruin_formed` record
  `exploration.md`'s substrate already stores.

## Status

Nothing in this doc below the geology substrate is implemented yet; this
section is the honest ledger and will be updated as slices land.

- ✅ **Substrate already in place** (from [geology.md](geology.md), not this
  doc): four configured `Strata` layers with real per-layer ore weighting,
  `TunnelSupport`'s real span-squared collapse model, `GeologyHazards`' foul
  air and flood risk, `CaveEntrancePlacement`, and the topsoil/regolith layer
  wired end-to-end and playable.
- ⬜ `Lithology`, `CaveRecharge`, `CavePattern`, `CaveNetwork`,
  `CaveZonation`, chemosynthetic energy, and cutoff grade -- all specified
  above, none built.
- ⬜ `Strata.KIND_VOID`, and the pitch/descent wiring from topsoil/regolith
  into bedrock. This is `geology.md`'s own standing ⬜ gap, restated here with
  the structure it was missing.
- ⬜ True-black rendering below the twilight zone, and the light gate on
  descent.
- ⬜ The underground clade: no creature pools, no chemosynthetic energy
  budget, no spawning.
- ⬜ Claims, gates, and lapse -- the whole "instancing without instances"
  mechanism is design only.
- ⬜ Lava tubes (basalt), specified above and deliberately not folded into the
  solutional model.
- ⬜ Saltpetre, speleothems-as-archives, chemosynthetic food, and cold storage.

## Open questions

- How large should a bedrock cave system be in tiles? Real systems span
  kilometres, which is far more than a chunk; the void field is per-chunk
  deterministic so it composes across chunks without a global pass, but
  whether that produces systems that *read* as continuous at player scale is
  an empirical question that needs playing, not deciding.
- Does the player carry a "current layer" as real state, or is depth a
  property of position? The former is simpler to render and reason about; the
  latter is truer to a world where a cave and the surface above it exist at
  the same time.
- How much of the chemosynthetic energy budget needs to be simulated per cell
  versus derived on demand from lithology plus hydrothermal proximity? The
  surface ecosystem sim answers the equivalent question with a per-cell field;
  the underground may not need one.
- Should a claim be enforceable against other players mechanically (a gate
  that actually stops them) or only socially/legally (a gate that marks
  ownership, with [governance.md](governance.md) deciding consequences)? The
  second is more interesting and much harder.
