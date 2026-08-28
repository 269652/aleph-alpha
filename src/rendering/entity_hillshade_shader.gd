extends RefCounted

## GPU relief shading for individual ENTITY sprites (see mountain_vein_sprite.gd,
## docs/concept/terrain_relief.md's "Hillshading"/"Mountain ore" sections) --
## a sibling to HillshadeShader, and structurally different from it in one
## way: HillshadeShader darkens a separate GROUND OVERLAY layer (a
## translucent black rectangle composited OVER the terrain tile beneath it)
## by sampling PER-PIXEL slope/aspect DATA baked into its own input
## texture. An entity sprite (a mountain vein) has no such separate layer
## to composite onto -- it darkens ITS OWN texture directly instead, and
## its slope/aspect is one fixed value for the whole sprite (a tile doesn't
## vary within one 32x32 icon), not per-pixel data to sample.
##
## sun_elevation_deg/sun_azimuth_deg are REGULAR (shared) uniforms -- the
## same real sun position applies to every entity at once, exactly like
## HillshadeShader's own uniforms, so one set_sun_position call re-shades
## every sprite sharing this material. slope_deg/aspect_deg are Godot 4's
## `instance uniform` -- a per-CanvasItem override on that SAME shared
## material, which is the whole point: many different vein sprites (each
## at a different tile, with its own fixed slope/aspect) can all share ONE
## material instance -- EarthChunkManager.set_sun_position only ever needs
## to update ONE shared material, exactly the existing HillshadeShader
## pattern, never a per-spawned-node update loop.
##
## Godot 4.7 (this project's engine -- see project.godot's config/features)
## has supported `instance uniform` in canvas_item shaders since 4.0, and
## CanvasItem.set_instance_shader_parameter/get_instance_shader_parameter
## are real, confirmed-live methods (see
## test_a_real_canvasitem_accepts_the_shared_materials_instance_uniforms,
## which exercises them for real rather than trusting this comment). This
## project has hit a real, hardware-measured instance-uniform caveat
## before -- IllustratedGrassPatch abandoned `instance uniform` for its
## per-card atlas region because it hits ONE GLOBAL, hardware-capped
## buffer shared by the whole scene (measured: 4096 slots total), which a
## single chunk's worth of grass blade instances already overflowed (see
## long_grass.md). That does not apply here: mountain veins are landmark-
## rare (MountainOrePlacement's own vein-chance ceiling, tuned for
## rarity), each a real, individual CanvasItem, nowhere near that count
## loaded at once -- nothing like grass's near-every-tile density.
##
## No early `return` inside fragment() -- Godot's shader compiler rejects
## that (this project hit the exact bug once already, see
## hillshade_shader.gd's own doc comment). This shader avoids the problem
## the same way: branches only ever SET `dim`, applied once at the end.

const Hillshade = preload("res://src/rendering/hillshade.gd")
const HillshadeShader = preload("res://src/rendering/hillshade_shader.gd")

const SHADER_CODE := """
shader_type canvas_item;

uniform float sun_elevation_deg = 45.0;
uniform float sun_azimuth_deg = 180.0;
uniform float min_lit_fraction = 0.45;

instance uniform float slope_deg = 0.0;
instance uniform float aspect_deg = -1.0;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	float dim = 1.0;
	if (sun_elevation_deg > 0.0) {
		float zenith_rad = radians(90.0 - sun_elevation_deg);
		float slope_rad = radians(slope_deg);
		float relative_azimuth_rad = radians(sun_azimuth_deg - aspect_deg);
		float illumination = cos(zenith_rad) * cos(slope_rad)
			+ sin(zenith_rad) * sin(slope_rad) * cos(relative_azimuth_rad);
		illumination = clamp(illumination, 0.0, 1.0);
		dim = mix(min_lit_fraction, 1.0, illumination);
	}
	COLOR = vec4(tex_color.rgb * dim, tex_color.a);
}
"""

## The floor brightness a fully-shadowed entity darkens to. Not a fresh
## eyeballed number -- it is `1.0 - HillshadeShader.MAX_SHADOW_ALPHA`, the
## exact same floor brightness the ground TILE beneath a vein already
## darkens to in full shadow (that shader composites a black overlay up to
## MAX_SHADOW_ALPHA opacity; this one multiplies colour down to the same
## floor from the other direction), so a vein in shadow reads as
## consistently lit with the rock around it rather than an unrelated
## second darkening curve. Pinned by
## test_min_lit_fraction_is_derived_from_hillshade_shaders_max_shadow_alpha.
const MIN_LIT_FRACTION := 1.0 - HillshadeShader.MAX_SHADOW_ALPHA

## Same default sun position as HillshadeShader -- one real sun, reused
## rather than retyped, so a material built before any live clock value has
## been pushed in shows the same plausible overcast-noon lighting the
## ground overlay itself defaults to.
const DEFAULT_SUN_ELEVATION_DEG := HillshadeShader.DEFAULT_SUN_ELEVATION_DEG
const DEFAULT_SUN_AZIMUTH_DEG := HillshadeShader.DEFAULT_SUN_AZIMUTH_DEG

var _shared_material: ShaderMaterial


func make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("min_lit_fraction", MIN_LIT_FRACTION)
	material.set_shader_parameter("sun_elevation_deg", DEFAULT_SUN_ELEVATION_DEG)
	material.set_shader_parameter("sun_azimuth_deg", DEFAULT_SUN_AZIMUTH_DEG)
	return material


func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material


## Pushes the real, live sun position into the shared material's REGULAR
## uniforms -- same "live value pushed into a shared uniform" shape
## HillshadeShader.set_sun_position already uses. slope_deg/aspect_deg are
## never touched here: those are per-CanvasItem instance uniforms, set once
## per sprite at spawn time (see StoneRenderer._build_mountain_vein_node),
## not live values that change as the clock advances.
func set_sun_position(elevation_deg: float, azimuth_deg: float) -> void:
	var material := shared_material()
	material.set_shader_parameter("sun_elevation_deg", elevation_deg)
	material.set_shader_parameter("sun_azimuth_deg", azimuth_deg)


## The CPU mirror of exactly what the shader's fragment() draws -- reuses
## Hillshade.illumination (the same shared formula HillshadeShader.shadow_alpha
## also mirrors) rather than reimplementing it, so this file owns only the
## rendering-specific dim-mapping/night policy, not the physics.
##
## Returns 1.0 (fully undimmed) at night, NOT 0.0 -- this differs from
## HillshadeShader.shadow_alpha's night case on purpose. Both defer to the
## same existing global day/night CanvasModulate tint rather than adding a
## second darkening of their own; they just land on opposite numeric
## outputs to express that same policy, because HillshadeShader ADDS a
## black overlay on top (so "add nothing" is alpha 0.0) while this shader
## MULTIPLIES a texture's own colour by a fraction (so "change nothing" is
## fraction 1.0).
static func lit_fraction(
	slope_deg: float, aspect_deg: float, sun_elevation_deg: float, sun_azimuth_deg: float
) -> float:
	if sun_elevation_deg <= 0.0:
		return 1.0
	var illumination := Hillshade.illumination(slope_deg, aspect_deg, sun_elevation_deg, sun_azimuth_deg)
	return lerpf(MIN_LIT_FRACTION, 1.0, illumination)
