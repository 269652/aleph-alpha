extends GutTest

## HousePanel: docs/concept/village_growth.md mechanism 5 -- the readout a
## click on a house opens. A pure consumer of
## EarthChunkManager.household_report_at's own Dictionary: it renders what
## it is handed and reaches for nothing else, so it can be driven entirely
## from a literal here.

const HousePanel = preload("res://scenes/house_panel.gd")
const HouseholdWellbeing = preload("res://src/emergence/household_wellbeing.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

var panel: HousePanel


func before_each():
	panel = HousePanel.new()
	add_child_autofree(panel)


func _home_report(overrides: Dictionary = {}) -> Dictionary:
	var report := {
		"building_id": "house_medium", "capacity": 2, "is_home": true,
		"household_id": "household:npc:7", "resident_name": "Mara Fenn",
		"resident_occupation": "herbalist", "wallet_balance": 14,
		"needs": {"food": 0.9, "shelter": 1.0, "income": 0.35, "community": 0.5},
		"happiness": 0.72, "productivity": 0.64, "settlement_productivity": 0.7,
	}
	for key in overrides:
		report[key] = overrides[key]
	return report


func test_a_fresh_panel_is_closed():
	assert_false(panel.is_open())
	assert_false(panel.visible)


func test_showing_a_house_opens_it_and_titles_it_with_the_buildings_real_name():
	panel.show_report(_home_report())
	assert_true(panel.is_open())
	assert_eq(panel.title_text(), BuildingCatalog.display_name_of("house_medium"))


func test_a_house_names_the_person_living_in_it_and_their_trade():
	panel.show_report(_home_report())
	var subtitle := panel.subtitle_text()
	assert_true(subtitle.contains("Mara Fenn"), "the readout names the person: %s" % subtitle)
	assert_true(subtitle.to_lower().contains("herbalist"), "and their trade: %s" % subtitle)


func test_every_need_is_shown_as_its_own_labelled_reading():
	panel.show_report(_home_report())
	var rows := panel.need_rows()
	assert_eq(rows.size(), HouseholdWellbeing.NEED_IDS.size())
	for need_id in HouseholdWellbeing.NEED_IDS:
		assert_true(rows.has(need_id), "%s must have a row of its own" % need_id)


## The bar is the number: a fully met need fills its bar, an unmet one
## leaves it empty, and half fills half.
func test_a_needs_bar_is_proportional_to_the_need_itself():
	panel.show_report(_home_report({"needs": {"food": 1.0, "shelter": 0.0, "income": 0.5, "community": 0.5}}))
	var rows := panel.need_rows()
	assert_almost_eq(float(rows["food"]["fill"]), HousePanel.BAR_WIDTH, 0.5)
	assert_almost_eq(float(rows["shelter"]["fill"]), 0.0, 0.5)
	assert_almost_eq(float(rows["income"]["fill"]), HousePanel.BAR_WIDTH * 0.5, 0.5)


## A need that has fallen short reads differently at a glance, so a village
## in trouble can be spotted without reading four numbers.
func test_an_unmet_need_is_coloured_as_a_warning():
	panel.show_report(_home_report({"needs": {"food": 0.1, "shelter": 1.0, "income": 1.0, "community": 1.0}}))
	var rows := panel.need_rows()
	assert_eq(rows["food"]["color"], HousePanel.NEED_WARN_COLOR)
	assert_eq(rows["shelter"]["color"], HousePanel.NEED_OK_COLOR)


func test_happiness_and_productivity_are_reported_as_readable_percentages():
	panel.show_report(_home_report())
	var summary := panel.summary_text()
	assert_true(summary.contains("72"), "happiness as a percentage: %s" % summary)
	assert_true(summary.contains("64"), "productivity as a percentage: %s" % summary)


func test_the_households_purse_is_shown():
	panel.show_report(_home_report())
	assert_true(panel.purse_text().contains("14"), "the household's real gold: %s" % panel.purse_text())


# -- a commons: reported as what it is, never given invented residents ----

func _commons_report() -> Dictionary:
	return {
		"building_id": "city_hall", "capacity": 0, "is_home": false,
		"household_id": "", "resident_name": "", "resident_occupation": "",
		"wallet_balance": 0, "needs": {}, "happiness": 0.0, "productivity": 0.0,
		"settlement_productivity": 0.55,
	}


func test_a_commons_opens_without_any_needs_rows():
	panel.show_report(_commons_report())
	assert_true(panel.is_open())
	assert_eq(panel.title_text(), BuildingCatalog.display_name_of("city_hall"))
	assert_true(panel.need_rows().is_empty(), "a hall has no needs of its own")


func test_a_commons_says_whose_it_is_rather_than_naming_a_resident():
	panel.show_report(_commons_report())
	assert_true(panel.subtitle_text().to_lower().contains("commons"), panel.subtitle_text())


func test_a_commons_still_reports_the_villages_own_productivity():
	panel.show_report(_commons_report())
	assert_true(panel.summary_text().contains("55"), panel.summary_text())


# -- closing ---------------------------------------------------------------

func test_an_empty_report_closes_the_panel():
	panel.show_report(_home_report())
	panel.show_report({})
	assert_false(panel.is_open())
	assert_false(panel.visible)


func test_close_closes_it():
	panel.show_report(_home_report())
	panel.close()
	assert_false(panel.is_open())


func test_reopening_on_another_house_replaces_the_previous_reading():
	panel.show_report(_home_report())
	panel.show_report(_home_report({"resident_name": "Bren Ash", "building_id": "house_small"}))
	assert_eq(panel.title_text(), BuildingCatalog.display_name_of("house_small"))
	assert_true(panel.subtitle_text().contains("Bren Ash"))
	assert_false(panel.subtitle_text().contains("Mara Fenn"), "no stale reading left behind")


# -- the Inventory tab (docs/concept/building_storage.md) -------------------
#
# Asked for directly: "it should be visible as inventory tab in the popover
# when you click a building". Drawn from the report like everything else
# here -- the panel reaches for nothing of its own.


func _stocked_report(stock: Dictionary, capacity: int = 60) -> Dictionary:
	return _home_report({"stock": stock, "storage_capacity": capacity})


func test_a_building_with_goods_in_it_offers_an_inventory_tab():
	panel.show_report(_stocked_report({"wheat": 12, "wood": 3}))
	assert_true(panel.has_inventory_tab(), "a building holding goods shows them")


func test_the_inventory_tab_lists_every_kind_of_goods_and_its_count():
	panel.show_report(_stocked_report({"wheat": 12, "wood": 3}))
	var rows := panel.inventory_rows()
	assert_eq(rows.size(), 2)
	var by_item := {}
	for row in rows:
		by_item[row["item_id"]] = int(row["count"])
	assert_eq(by_item.get("wheat", 0), 12)
	assert_eq(by_item.get("wood", 0), 3)


## Goods are named the way the rest of the game names them, not by raw id.
func test_the_inventory_names_goods_the_way_the_game_does():
	panel.show_report(_stocked_report({"wheat": 1}))
	var items = load("res://src/gameplay/item_catalog.gd").new()
	assert_eq(panel.inventory_rows()[0]["label"], items.display_name_of("wheat"))


## How full it is, because "12 wheat" means nothing without the barn's size
## -- and a full barn is the whole reason hauling exists.
func test_the_inventory_says_how_full_the_building_is():
	panel.show_report(_stocked_report({"wheat": 45}, 60))
	assert_eq(panel.inventory_summary_text(), "Stored: 45 / 60")


func test_a_full_building_says_so():
	panel.show_report(_stocked_report({"wheat": 60}, 60))
	assert_true(panel.inventory_is_full(), "a full barn is why anyone hauls anything")


func test_a_building_below_its_own_capacity_is_not_full():
	panel.show_report(_stocked_report({"wheat": 59}, 60))
	assert_false(panel.inventory_is_full())


## A building that keeps no goods has no tab at all, rather than an empty
## one: a town hall is not a barn with nothing in it.
func test_a_building_that_keeps_no_goods_has_no_inventory_tab():
	panel.show_report(_home_report({"stock": {}, "storage_capacity": 0}))
	assert_false(panel.has_inventory_tab())


## An EMPTY barn still has a tab -- it holds goods, it just has none right
## now, and that is a fact worth showing.
func test_an_empty_barn_still_shows_its_inventory():
	panel.show_report(_stocked_report({}, 60))
	assert_true(panel.has_inventory_tab())
	assert_eq(panel.inventory_rows().size(), 0)
	assert_eq(panel.inventory_summary_text(), "Stored: 0 / 60")


## An older report with no stock in it at all must not crash the panel --
## the same fail-soft every other field here already has.
func test_a_report_that_says_nothing_about_stock_shows_no_tab():
	panel.show_report(_home_report())
	assert_false(panel.has_inventory_tab())


# -- a thing that is not a building (docs/concept/village_warehouse.md, 6) --
#
# Asked directly: "clicking on it shows the popup with inventory". The
# question a cart answers is the same question a barn answers, and this panel
# is already a pure consumer of a Dictionary -- so a cart hands it one rather
# than growing a second panel that draws the same rows a different way.

const CartLoad = preload("res://src/gameplay/cart_load.gd")


func _cart_report(overrides: Dictionary = {}) -> Dictionary:
	var report := {
		"title": "Handcart (6)", "subtitle": "Pulled by Ilsa Rook", "is_home": false,
		"stock": {"beam": 4, "plank": 2}, "storage_capacity": CartLoad.CAPACITY,
	}
	for key in overrides:
		report[key] = overrides[key]
	return report


func test_a_report_that_names_itself_is_titled_by_that_name():
	panel.show_report(_cart_report())
	assert_eq(panel.title_text(), "Handcart (6)", "not looked up in a building catalog")
	assert_eq(panel.subtitle_text(), "Pulled by Ilsa Rook", "nor called a settlement commons")


## And a building still names itself the way it always did -- it carries
## neither key, so nothing that already opened this panel changes.
func test_a_building_is_still_named_by_its_catalog_entry():
	panel.show_report(_home_report())
	assert_eq(panel.title_text(), BuildingCatalog.display_name_of("house_medium"))
	assert_true(panel.subtitle_text().contains("Mara Fenn"))


func test_a_carts_load_is_drawn_in_the_inventory_tab():
	panel.show_report(_cart_report())
	assert_true(panel.has_inventory_tab(), "a wagon is a shelf")
	var rows: Array = panel.inventory_rows()
	assert_eq(rows.size(), 2)
	assert_eq(rows[0].get("item_id"), "beam", "stable order, by item id")
	assert_eq(int(rows[0].get("count")), 4)
	assert_true(panel.inventory_summary_text().contains(str(CartLoad.CAPACITY)))


## An empty cart still opens -- "there is nothing in it" is a real answer.
func test_an_empty_cart_still_opens_and_says_it_is_empty():
	panel.show_report(_cart_report({"title": "Handcart", "stock": {}}))
	assert_true(panel.is_open())
	assert_true(panel.inventory_rows().is_empty())
	assert_false(panel.inventory_is_full())
