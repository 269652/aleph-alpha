extends SceneTree

## Where are a rail panel's own posts, and how far apart?
##
## Reported live with an enclosure in shot: *"the enclosures render
## unnecessary vertical rails"*. Every cell of fence.png is a WHOLE panel --
## a post at EACH end with rails between (see the sheet's own four columns) --
## and _footprint_scale sizes a straight rail so its whole RUN LENGTH is one
## tile, posts included. So each panel's two posts land INSIDE its tile while
## consecutive tiles sit a whole tile apart, and every junction shows two
## posts a few pixels apart instead of one.
##
## Measured at the drawn size: posts 12.5 px apart inside a 16 px tile. This
## reports the same thing at SOURCE resolution, where the caps are
## unambiguous, because that is where _footprint_scale does its arithmetic.

const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")

const RAILS := ["farm_fence_north", "farm_fence_south", "farm_fence_east", "farm_fence_west"]


## The centres of the panel's two END bands along `vertical_run`'s axis. A
## panel always carries a post at each end, so the end bands ARE the posts.
func _post_spacing(image: Image, vertical_run: bool) -> float:
	var along := image.get_height() if vertical_run else image.get_width()
	var across := image.get_width() if vertical_run else image.get_height()
	var coverage: Array[float] = []
	var peak := 0.0
	for i in range(along):
		var opaque := 0
		for j in range(across):
			var c := image.get_pixel(j, i) if vertical_run else image.get_pixel(i, j)
			if c.a > 0.5:
				opaque += 1
		var v := float(opaque) / float(across)
		coverage.append(v)
		peak = maxf(peak, v)
	# a coarse profile of the real source coverage, so the detector is chosen
	# from what the art looks like rather than from a guess about it
	var buckets: Array[String] = []
	var step: int = maxi(1, along / 40)
	for b in range(0, along, step):
		var total := 0.0
		var n := 0
		for i in range(b, mini(b + step, along)):
			total += coverage[i]
			n += 1
		buckets.append("%.2f" % (total / float(maxi(n, 1))))
	print("SRCPROFILE along=%d %s" % [along, ", ".join(buckets)])
	# A post spans the panel's whole cross-axis; the rails between the posts
	# span only their own two bars, at roughly half that. So classify against
	# the RAIL level -- the median of the slices that have any content at all
	# -- rather than against the peak: the trimmed art carries stray edge
	# slices (one fully opaque column at the far end, a few near-empty ones
	# at the near end) that own the peak and swallow the whole run.
	#
	# A real post is also WIDE. Requiring a band of at least 2% of the run
	# rejects those same one-column strays on width alone, whatever their
	# coverage.
	var content: Array[float] = []
	for v in coverage:
		if v > 0.02:
			content.append(v)
	if content.size() < 3:
		return 0.0
	content.sort()
	var rail_level: float = content[content.size() / 2]
	var threshold := rail_level * 1.4
	var min_width: int = maxi(2, int(round(float(along) * 0.02)))
	var bands: Array = []
	var run_start := -1
	for i in range(along):
		var is_post: bool = coverage[i] >= threshold
		if is_post and run_start < 0:
			run_start = i
		if (not is_post) and run_start >= 0:
			if i - run_start >= min_width:
				bands.append([run_start, i - 1])
			run_start = -1
	if run_start >= 0 and along - run_start >= min_width:
		bands.append([run_start, along - 1])
	if bands.size() < 2:
		return 0.0
	var first: Array = bands[0]
	var last: Array = bands[bands.size() - 1]
	var first_centre := (float(first[0]) + float(first[1])) * 0.5
	var last_centre := (float(last[0]) + float(last[1])) * 0.5
	return last_centre - first_centre


func _initialize() -> void:
	var sprites := IllustratedStructureSprite.new()
	var tile := TerrainRenderer.TILE_SIZE
	for subject in RAILS:
		var idle := sprites.idle_texture(subject)
		if idle == null:
			print("RESULT %s idle=null" % subject)
			continue
		var source := idle.get_image()
		var inner: Vector2i = VillageFarm.fence_inner_direction(subject)
		var vertical_run := inner.x != 0
		var along := source.get_height() if vertical_run else source.get_width()
		var spacing := _post_spacing(source, vertical_run)
		var drawn := sprites.footprint_texture(subject, tile).get_image()
		var drawn_along := drawn.get_height() if vertical_run else drawn.get_width()
		var now_scale := float(drawn_along) / float(maxi(along, 1))
		print(
			"RESULT %s source_along=%d post_spacing=%.1f (%.4f of it) | drawn_along=%d current_scale=%.4f -> posts %.2f apart | want_scale=%.4f (posts exactly %d apart)"
			% [
				subject, along, spacing, spacing / float(maxi(along, 1)),
				drawn_along, now_scale, spacing * now_scale,
				float(tile) / maxf(spacing, 1.0), tile,
			]
		)
	quit()
