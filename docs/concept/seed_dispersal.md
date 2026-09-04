# Seeds and how they travel

How a plant gets its offspring somewhere other than directly underneath
itself. Covers the wind, the animals that eat seed and carry it, and what
happens to a seed once it is on the ground.

## Design pillars

**A seed is a thing in the world, not a number.** Where a seed is, you can see
it: it lies on the ground, it blows about, a bird can eat it, rain can root it.
A dispersal system that only moves numbers between tiles gives the player
nothing to watch and nothing to interfere with.

**Light things go further.** This is the whole reason plants have different
seeds. A dandelion seed and an acorn fall from the same height in the same
wind and land a hundred metres apart, and that difference is why meadows
colonise faster than woods. Weight is the single property that decides how far
a seed travels.

**Most seed lands near, a little lands far.** Real wind dispersal is heavy
tailed: the bulk of a plant's seed falls within a few body-widths, and a small
fraction goes a very long way. That tail is what actually colonises new ground,
and a uniform scatter -- everything at roughly the same distance -- gives
neither a dense home patch nor any pioneers.

**The weather decides, not the plant.** Wind has a strength and a direction on
any given day, and both apply to everything dispersing that day. A meadow
should visibly creep downwind over seasons rather than expanding as a circle,
because that is the fingerprint of wind actually being simulated rather than a
random offset wearing wind's name.

## Real-world grounding

Wind dispersal distance is modelled as a heavy-tailed distribution around a
downwind mean. The two inputs are the seed's own **terminal velocity** -- which
here is simply its weight class -- and the **wind speed** on the day. A light
seed in a strong wind travels furthest; a heavy seed in still air drops
straight down.

Weight classes, in the order the real seeds fall:

| seed | weight | why |
|---|---|---|
| flower seed | very light | plumed or dust-fine, built for wind |
| berry pip | light | small, but no plume |
| tree fruit | heavy | carried by animals, not air |
| nut | very heavy | drops within a crown-width, always |

Direction varies day to day rather than being fixed: a prevailing wind that
never turned would drive every meadow in the world in one direction forever.

## Mechanism

**Wind.** Each day has a strength (already modelled per weather state, see
`WeatherModel.wind_strength_for`) and a direction. Both are derived from the
day and the region, so every plant dispersing on the same day in the same place
agrees about the wind without anything being passed between them.

**Where a seed lands.** A downwind displacement proportional to wind strength
and to the seed's lightness, plus a scatter that does not depend on the wind at
all -- so a seed released in dead calm still lands *somewhere*, just not far.
Distance is drawn from a heavy-tailed roll so most seed lands close and a few
go a long way.

**A seed needs earth.** Rain alone does not root anything: the seed has to be
lying on ground that can actually take it. Water, bare rock and sand are not
seedbeds, and neither is anything built or paved over.

Bare earth is a far better seedbed than dense turf, which is true and is the
reason disturbance drives succession in the first place: a seed that lands in
thick grass mostly fails, and the same seed on scraped ground mostly takes.
That makes clearing a patch the way a player deliberately starts a wood, and it
makes the trampled dirt of a path (see `PathScarring`, which already renders
worn tiles as earth) a nursery rather than merely a scar.

**Landing is not establishing.** The seed shadow and the standing plants are
two different distributions, and conflating them is what makes a modelled
meadow read as a mat rather than as a meadow. Seed rain is densest directly
under the parent; *survival* there is close to nil — the seedling is
competing with an established root system for the same water and light, it
sits in the highest concentration of that plant's own pathogens, and it is
precisely where that plant's seed predators are already working. Only seed
that escapes the parent's neighbourhood becomes a plant (the **Janzen–Connell**
effect). So the kernel above stays heavy tailed and honest, and a separate,
explicit **establishment** gate decides which of that seed actually roots:
nothing takes within a minimum spacing of an already-standing plant of its
kind (`FlowerEstablishment`). That gate is what sets how far apart plants
stand; the kernel sets where the clumps are and which way they are drawn out.

**The world you arrive to has already dispersed.** Baked worldgen is not
exempt from any of this. A newly generated meadow is produced by running this
same kernel from sparse founder plants under the region's **prevailing wind**
(`WeatherModel.prevailing_wind_direction`, the long-run wind rather than one
day's), through the same establishment gate, in world space so it crosses
chunk boundaries — see [flora.md](flora.md#the-meadow-you-arrive-to-is-what-the-wind-already-did).
A world whose whole dispersal story is "light seed goes downwind" must not
*start* isotropic and only become windswept for a player who stands and
watches.

**Rooting.** A seed on the ground is still a seed: it can be eaten, blown
further, or picked up. **Rain is what roots it.** Once rooted it is a sapling,
and a sapling is no longer food -- a bird that would have eaten the seed leaves
the seedling alone, because it is not a seed any more.

## Status

- ✅ Wind direction and strength per day and region
- ✅ Heavy-tailed, downwind, weight-dependent landing offsets
- ✅ Seeds as real world entities: drawn, eaten by birds, and picked up
- ✅ Germination needing earth, with bare ground a far better seedbed than turf
- ⬜ Rain rooting a lying seed into a sapling
- ✅ Bird hunger, and a dropping where the seed comes out
- ⬜ Wind derived from real climate models rather than from the weather state
