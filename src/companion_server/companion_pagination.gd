extends RefCounted

## Pure, generic list pagination -- no knowledge of items/recipes/anything
## companion-server-specific, so any future paginated view can reuse it.
## See companion_item_catalog_view.gd for the first consumer.

static func paginate(items: Array, page: int, page_size: int) -> Dictionary:
	var total_count := items.size()
	# Integer ceil-div, not a float ceil() call. Floored at 1: a zero-match
	# search is the NORMAL shape of using a search box, not a rare edge
	# case, and "page 1 of 1" is the only renderable answer for it -- "page
	# 1 of 0" has no sensible meaning and would make every clamp below
	# ill-defined (clamping into an empty range).
	var total_pages: int = maxi(1, (total_count + page_size - 1) / page_size)
	var clamped_page := clampi(page, 1, total_pages)
	var start := (clamped_page - 1) * page_size
	var end := mini(start + page_size, total_count)
	return {
		"items": items.slice(start, end),
		"page": clamped_page,
		"total_pages": total_pages,
		"total_count": total_count,
	}
