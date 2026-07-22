extends GutTest

var ImpactResolver: GDScript = preload("res://src/gameplay/impact_resolver.gd")

var resolver: RefCounted


func before_each() -> void:
	resolver = ImpactResolver.new()


func test_low_momentum_always_bounces() -> void:
	assert_eq(resolver.resolve_impact(0.5, "edge", "iron"), "bounce")


func test_edge_below_cut_threshold_dents() -> void:
	assert_eq(resolver.resolve_impact(2.0, "edge", "wood"), "dent")


func test_edge_at_cut_threshold_cuts_tough_material() -> void:
	assert_eq(resolver.resolve_impact(3.0, "edge", "wood"), "cut")


func test_edge_on_brittle_material_shatters_instead_of_cutting() -> void:
	assert_eq(resolver.resolve_impact(3.0, "edge", "obsidian"), "shatter")


func test_blunt_below_crush_threshold_dents() -> void:
	assert_eq(resolver.resolve_impact(3.5, "blunt", "wood"), "dent")


func test_blunt_at_crush_threshold_crushes_tough_material() -> void:
	assert_eq(resolver.resolve_impact(4.0, "blunt", "wood"), "crush")


func test_blunt_on_brittle_material_shatters_instead_of_crushing() -> void:
	assert_eq(resolver.resolve_impact(4.0, "blunt", "obsidian"), "shatter")


func test_point_at_pierce_threshold_pierces_soft_material() -> void:
	assert_eq(resolver.resolve_impact(3.0, "point", "flesh"), "pierce")


func test_point_cannot_pierce_hard_material() -> void:
	assert_eq(resolver.resolve_impact(3.0, "point", "iron"), "dent")


func test_point_below_pierce_threshold_dents() -> void:
	assert_eq(resolver.resolve_impact(2.0, "point", "flesh"), "dent")


func test_unknown_geometry_dents() -> void:
	assert_eq(resolver.resolve_impact(5.0, "sideways", "wood"), "dent")
