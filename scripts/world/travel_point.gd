extends Interactable
class_name TravelPoint
## TravelPoint - Road out of a region. Opens the travel map for long journeys
## Placed in gate scenes; the travel system (TravelMap autoload) owns the actual journey

## Location ID this travel point stands in (must match resources/world/world.json)
@export var from_location: String = ""

func _ready():
	super._ready()
	add_to_group("travel_points")
	if interaction_name == "Interact":
		interaction_name = "Travel"

func _on_interact():
	var travel_map = get_node_or_null("/root/TravelMap")
	if travel_map and travel_map.has_method("open"):
		travel_map.open(from_location)
	else:
		push_warning("[TravelPoint] No TravelMap autoload; cannot travel from %s" % from_location)
