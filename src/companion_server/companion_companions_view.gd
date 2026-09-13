extends RefCounted

## Renders Player.to_save_dict()'s bonded_companions list -- a plain
## [{"species": String}, ...] array, nothing richer persisted for THAT
## specific list. See docs/concept/companion_server.md's Companions
## section for why this is deliberately narrower than a full bestiary (no
## encounter-tracking mechanism exists anywhere in this codebase to build
## one from).
##
## A second, real data source is layered in alongside it: `kept_animals`,
## the flattened, chunk-tagged output of CompanionKeptAnimalsReader.read_all()
## (src/world/kept_animals.gd's own per-chunk trust/order/is_tied/tied_to/
## wander_seed records). Defaults to an empty array so every existing
## single-argument call site (including every pre-existing test) stays
## green -- this is additive, not a breaking reshape of the view.

const CompanionPageShell = preload("res://src/companion_server/companion_page_shell.gd")
const CompanionHtml = preload("res://src/companion_server/companion_html.gd")
const AnimalFitness = preload("res://src/world/animal_fitness.gd")
const Taming = preload("res://src/gameplay/taming.gd")

static var _fitness := AnimalFitness.new()


static func render(save_dict: Dictionary, kept_animals: Array = []) -> String:
	var companions: Array = save_dict.get("bonded_companions", [])
	var body: String
	if companions.is_empty():
		body = "<p>No companions yet -- tame or net one to see it here.</p>"
	else:
		body = "<ul>"
		for companion in companions:
			body += "<li>%s</li>" % CompanionHtml.escape(String(companion.get("species", "?")))
		body += "</ul>"
	body += "<h2>Kept Animals</h2>"
	body += _render_kept_animals(kept_animals)
	return CompanionPageShell.wrap("Companions", body)


## Trust runs 0..Taming.TAME_TRUST (1.0, "fully tame" -- the exact same
## threshold Taming.is_tame() already gates real gameplay on, reused rather
## than inventing a second, eyeballed trust scale just for display). A tied
## animal that hasn't warmed up yet (trust still 0) gets its own label
## instead of reading as merely "Wary", since the player put it there on
## purpose (KeptAnimals.is_worth_keeping's own reasoning).
static func _trust_stage_for(trust: float, is_tied: bool) -> String:
	if Taming.is_tame(trust):
		return "Tame"
	if trust > 0.0:
		return "Bonding"
	if is_tied:
		return "Tied, not yet trusting"
	return "Wary"


static func _render_kept_animals(kept_animals: Array) -> String:
	if kept_animals.is_empty():
		return "<p>No kept animals yet -- tie one up or tame it to see it here.</p>"
	var body := "<ul>"
	for animal in kept_animals:
		body += "<li>%s</li>" % _render_kept_animal_row(animal)
	body += "</ul>"
	return body


static func _render_kept_animal_row(animal: Dictionary) -> String:
	var species := CompanionHtml.escape(String(animal.get("species", "?")))
	var chunk_coord: Vector2i = animal.get("chunk_coord", Vector2i.ZERO)
	var trust := float(animal.get("trust", 0.0))
	var is_tied := bool(animal.get("is_tied", false))
	var order := int(animal.get("order", Taming.ORDER_FOLLOW))
	var wander_seed := int(animal.get("wander_seed", 0))

	var tied_label := "Tied" if is_tied else "Loose"
	var order_label := "Stay" if order == Taming.ORDER_STAY else "Follow"
	var trust_stage := _trust_stage_for(trust, is_tied)
	var fitness_score := _fitness.fitness_score(_fitness.phenotype_for(wander_seed))

	return (
		"%s -- chunk (%d, %d) -- %s -- %s -- %s -- fitness %.2f"
		% [species, chunk_coord.x, chunk_coord.y, tied_label, order_label, trust_stage, fitness_score]
	)
