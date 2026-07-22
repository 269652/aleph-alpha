extends RefCounted

## Coziness/Appeal Score (docs/concept/housing.md) -- how appealing a placed
## furniture arrangement is. Fixed table, no randomness; thematic coherence
## (a matched set) scores higher than an equally-priced pile of clutter.

## furniture_id -> {"base_appeal": float, "theme": String}
const _FURNITURE := {
	"wooden_chair": {"base_appeal": 3.0, "theme": "rustic"},
	"stone_hearth": {"base_appeal": 6.0, "theme": "rustic"},
	"oak_table": {"base_appeal": 4.0, "theme": "rustic"},
	"steel_lamp": {"base_appeal": 3.0, "theme": "modern"},
	"glass_shelf": {"base_appeal": 4.0, "theme": "modern"},
	"chrome_stool": {"base_appeal": 2.0, "theme": "modern"},
	"wool_rug": {"base_appeal": 3.0, "theme": "cozy"},
	"knit_blanket": {"base_appeal": 2.0, "theme": "cozy"},
	"candle_set": {"base_appeal": 1.5, "theme": "cozy"},
}

## A theme with 3+ placed items counts as a matched set and earns a bonus
## equal to this fraction of that theme's contributing items' base_appeal
## sum, on top of the plain sum. Multiple qualifying themes each earn their
## own bonus independently.
const _COHERENCE_BONUS_RATIO := 0.2
const _COHERENCE_THRESHOLD := 3


## Sum of each known item's base_appeal, plus a coherence bonus for every
## theme with _COHERENCE_THRESHOLD or more placed items (see
## _COHERENCE_BONUS_RATIO). Unknown ids contribute 0 rather than crashing.
func total_score(furniture_ids: Array) -> float:
	var total: float = 0.0
	var theme_subtotals: Dictionary = {}
	var theme_counts: Dictionary = {}
	for furniture_id in furniture_ids:
		if not _FURNITURE.has(furniture_id):
			continue
		var entry: Dictionary = _FURNITURE[furniture_id]
		var appeal: float = entry["base_appeal"]
		var theme: String = entry["theme"]
		total += appeal
		theme_subtotals[theme] = theme_subtotals.get(theme, 0.0) + appeal
		theme_counts[theme] = theme_counts.get(theme, 0) + 1
	for theme in theme_counts:
		if theme_counts[theme] >= _COHERENCE_THRESHOLD:
			total += theme_subtotals[theme] * _COHERENCE_BONUS_RATIO
	return total


## Theme with the most placed items among furniture_ids (unknown ids
## ignored). Empty string when the list has no known items, or when the
## top count is shared by two or more themes -- ties are not broken.
func dominant_theme(furniture_ids: Array) -> String:
	var theme_counts: Dictionary = _count_themes(furniture_ids)
	var best_theme: String = ""
	var best_count: int = 0
	var tied: bool = false
	for theme in theme_counts:
		var count: int = theme_counts[theme]
		if count > best_count:
			best_count = count
			best_theme = theme
			tied = false
		elif count == best_count:
			tied = true
	if tied:
		return ""
	return best_theme


func _count_themes(furniture_ids: Array) -> Dictionary:
	var theme_counts: Dictionary = {}
	for furniture_id in furniture_ids:
		if not _FURNITURE.has(furniture_id):
			continue
		var theme: String = _FURNITURE[furniture_id]["theme"]
		theme_counts[theme] = theme_counts.get(theme, 0) + 1
	return theme_counts
