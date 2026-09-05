# Terrain Biome Borders

**Superseded — merged into [`terrain_borders.md`](terrain_borders.md).**

This doc and `terrain_borders.md` specified the exact same system (biome
border dithering and corner carving in `TerrainRenderer`) independently —
this one was written second, roughly two weeks after the other, without
either doc ever referencing the other. The two had already drifted apart
by the time this was found (2026-09-05 cross-alignment pass, see
`docs/progress.md`): this doc had the earth-modification blend mechanism
and a more honest accounting of open gaps that `terrain_borders.md` was
missing, while `terrain_borders.md` alone had the most recent
staircase-corner fix, which this doc never received.

`terrain_borders.md` stays canonical — `src/rendering/terrain_renderer.gd`
and `tests/unit/test_terrain_renderer.gd` already cite it by name in three
places, and it predates this doc. Everything this doc specified that the
other was missing (the earth-modification blend section, the "deliberately
out of scope" gaps, the corresponding 🚧/⬜ status entries) has been merged
forward into it. Read `terrain_borders.md` instead; nothing further here
will be kept current.
