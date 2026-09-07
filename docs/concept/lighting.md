# Lighting

How the world gets darker at night, and how a carried light source pushes
back against that darkness. The day/night half of this already existed in
code (`scenes/world.gd`) with no concept doc of its own — documented here
for the first time, since the new torch mechanism has to sit correctly
alongside it rather than fight it.

## Design pillars

1. **Night is dim, never pitch black.** Real-world grounding, already
   established by `world.gd`'s own `NIGHT_TINT` comment: moonlight +
   starlight + skyglow give real usable outdoor vision even with the sun
   fully below the horizon. A carried light source is what turns "dim and
   readable" into "genuinely lit," not what turns "black" into "visible."
2. **A light source adds, it does not fight the global tint.** The
   day/night cycle is one global multiply over the whole screen
   (`CanvasModulate`) — the same mechanism every sprite in the game
   already renders under, including ones with their own custom shaders
   (grass, water, terrain) that define no per-light response at all. A
   local light cannot selectively "undo" that multiply for one area
   without either rewriting every existing shader to respond to a real
   Godot `Light2D` (a large, invasive change with an uncertain payoff — a
   fragment shader with no `light()` callback does not respond to
   `Light2D` regardless of the renderer) or layering something on top. An
   ADDITIVE glow, rendered after the tint, sidesteps this entirely: it
   reads correctly over grass, water, terrain and the player alike, with
   zero changes to any existing shader.
3. **Cost must not scale with anything but "is a light source currently
   equipped."** One push of a world position and an on/off (or intensity)
   value per frame when something is lit, matching the exact shape
   `EarthChunkManager.set_wind_strength`/`IllustratedGrassPatch.
   set_walker_position` already use — never a per-tile or per-chunk cost.

## Real-world grounding

A hand-held torch or campfire realistically throws useful light out to
roughly 6-9 metres before it fades into the surrounding dark — enough to
see the ground immediately around you and make out shapes a few paces
off, not enough to light a whole clearing like daylight. Converted via
`GroundSlide.PX_PER_METER` (this codebase's one real-world-scale-to-pixel
conversion, already used throughout `flyer_personality.gd`/
`footstep_gait.gd`), that sets the real radius a torch's glow should
reach.

## Mechanism

### The existing day/night cycle (undocumented until now)

`scenes/world.tscn` has one `CanvasModulate` node (`DayNightTint`),
updated once per frame in `World._client_process`. The real sun elevation
(`SolarPosition.elevation_degrees`, latitude/longitude/day-of-year aware)
feeds `SolarPosition.sunlight_intensity(elevation)` — a `[0,1]` scalar —
into `World.day_night_tint_for(sunlight)`, a plain linear interpolation
between `NIGHT_TINT` (`Color(0.4, 0.4, 0.55)`, a dim, cool, blue-shifted
floor — see that constant's own doc comment, "I can barely see at night"
was a real report against an even darker previous floor) and `DAY_TINT`
(`Color(1,1,1)`, neutral/undimmed). `CanvasModulate` multiplies every
rendered pixel in the viewport by this color, which is why it is a global
effect no per-object shader needs to opt into.

`/day`, `/night` and `/time` (console commands) all resolve through the
single `forced_elevation_for` seam so they can never disagree with each
other or with a live override about which sky wins.

### Torch: a per-frame-pushed additive glow, gated on equip

`TorchGlow` (`src/rendering/torch_glow.gd` + a `TorchGlow` node under
`World`, mirroring `DayNightTint`'s own "one node, `$NodeName`, updated
every frame" shape exactly) is a `canvas_item` fragment shader on a fixed
quad, additive blend (`render_mode blend_add;`), centered on the player's
world position and pushed there every frame the same way grass already
receives `player_world_position`. A radial falloff
(`glow_intensity(distance, radius) -> float`, mirrored in GDScript per
this codebase's own "a fragment shader cannot be asserted headless, mirror
the tuned math" convention — see `SnowSparkleShader`/`WaterShader`) gives a
warm, soft-edged circle of added brightness rather than a hard-edged disc.

**Gated on `Player.equipped_item.id == "torch"`, nothing else.** A torch
has no fuel/ignition state modeled (`item_catalog.gd` never lists it in
`_WEAPON_MATERIAL_AND_VOLUME`, so `ItemWear.condition_for` always reports
it `"pristine"` — it cannot even model "broken" today) — equipping it
IS the same thing as it being lit, the simplest honest reading of "hold a
torch, get light" without inventing a second mechanic nobody asked for. If
a real ignite/extinguish toggle is wanted later, this is the one seam that
would need to grow a second condition, not a redesign.

**Deliberately not gated on time of day.** An additive glow tuned for
night visibility is nearly invisible added on top of an already-bright
daytime scene (adding warmth to already-bright pixels does very little
perceptually) — the exact same reason a real torch carried at noon does
not visibly change how bright the ground looks. The glow can stay
unconditionally on whenever a torch is equipped; it reads as useful
exactly when it needs to, for free, without an explicit day/night branch
in the gating logic.

## Status

- 🚧 In progress this pass — see `docs/progress.md`.
