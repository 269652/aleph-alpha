## Combat

Real-time, top-down, arcade-tactical — **Hammerwatch** as the base feel
(fast movement, cooldown-based abilities, twitchy dodge-and-position combat,
co-op friendly), with a few **Baldur's Gate 3**-flavored tactical layers that
are achievable in 2D:

- Knockback into environmental hazards (fire, water, cliffs/ledges).
- Spreadable environmental effects (oil + fire, grass fires).
- Elevation via layered tilemaps (height advantage, line-of-sight blocking).
- Concealment tied directly into the ecosystem sim — tall/dense vegetation
  breaks line of sight, so a lush biome plays differently than a barren one
  (see [world.md](world.md)).
- Weather as another environmental lever — rain douses fire/oil, fog
  blocks line of sight independent of vegetation (see
  [weather.md](weather.md)).
- Throwables and simple physics-driven interactions (weight/knockback), in
  the spirit of "kill it by dropping/throwing something heavy on it," without
  committing to a full 3D physics-driven combat system at MVP.

Stat/skill/class/equipment systems and PvP/PvE are standard RPG scaffolding
on top of this — not novel on their own, but see [skills.md](skills.md),
[classes.md](classes.md), and [items.md](items.md) for this project's twist
on each.
