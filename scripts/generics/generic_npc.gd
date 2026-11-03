extends "res://scripts/npcs/base_npc.gd"
# GenericNPC - A scene body for one generic instance (scenes/npcs/generic_npc.tscn)
# The NpcSpawner instances it per population and calls setup(id). BaseNPC's conversation flow runs
# unchanged on a runtime NPCPersonality; every analysed interaction also layers on the instance.
# Tier generic: in-memory RAG only (its layers are its memory). Promoted: its own ChromaDB collection

var generic_id: String = ""
var archetype_id: String = ""
## GeneratableCharacter falls back to this pregenerated sprite (sprites are reused by archetype)
var character_type: String = "villager_male"

func _ready():
	add_to_group("npcs")
	add_to_group("generics")

func _manager() -> Node:
	var registry = get_node_or_null("/root/DynamicNPCRegistry")
	return registry.generics if registry and "generics" in registry else null

## Bind this body to an instance. Safe before the node enters the tree
func setup(id: String, manager: Node = null) -> void:
	if manager == null:
		manager = _manager()
	var inst = manager.get_instance(id) if manager else null
	if inst == null:
		push_warning("[GenericNPC] Unknown generic '%s'" % id)
		return
	generic_id = id
	archetype_id = inst.archetype_id
	npc_id = id
	npc_name = inst.name
	name = "Generic_" + id
	home_location = inst.home
	current_location = manager.get_location(id)
	character_type = manager.sprite_for(id)
	personality_resource = manager.build_personality(id)
	var gen = get_node_or_null("GeneratableCharacter")
	if gen:
		gen.character_id = character_type
	var label = get_node_or_null("NameLabel")
	if label:
		label.text = inst.name
	var sprite = get_node_or_null("AnimatedSprite2D")
	if sprite:
		sprite.modulate = manager.tint_for(id)

## Generic tier never opens a ChromaDB collection; promoted generics do (when the game uses one)
func initialize(use_chromadb: bool = true, enable_kpi_tracking: bool = false) -> bool:
	var manager = _manager()
	var use_db = use_chromadb and manager != null and manager.wants_chroma(npc_id)
	return await super.initialize(use_db, enable_kpi_tracking)

## Analysed interactions layer on the instance (after BaseNPC stores and scores them)
func record_interaction(interaction_type: String, context: Dictionary) -> void:
	await super.record_interaction(interaction_type, context)
	var manager = _manager()
	if manager:
		manager.record_interaction(npc_id, interaction_type, context)

func _store_learned_player_info(player_info: Dictionary) -> void:
	await super._store_learned_player_info(player_info)
	var manager = _manager()
	if manager:
		manager.record_learned(npc_id, player_info)

## Layers or nudges changed: rebuild the runtime personality (traits drift)
func refresh_from_instance() -> void:
	var manager = _manager()
	if manager and manager.get_instance(npc_id):
		personality_resource = manager.build_personality(npc_id)
		if personality_resource:
			system_prompt = personality_resource.generate_system_prompt()

## Combat's view of a generic: BaseNPC's, with minor answered by the archetype header (GenericManager)
func get_combat_profile() -> Dictionary:
	var profile = super.get_combat_profile()
	var manager = _manager()
	if manager and manager.has_method("is_minor") and manager.is_minor(generic_id if generic_id != "" else npc_id):
		profile["minor"] = true
		profile["weapon"] = "fists"  # a child carries nothing, whatever the body was given
		profile["armour"] = []
	return profile

## A generic is the kind of person its archetype's `type:` makes it (GenericManager.character_kind)
func character_kind() -> Dictionary:
	var manager = _manager()
	if manager and manager.has_method("character_kind"):
		return manager.character_kind(generic_id if generic_id != "" else npc_id)
	return super.character_kind()

## A generic fights with its archetype's loadout (resources/combat/loadouts.json `archetypes`)
func combat_loadout(minor: bool = false) -> Dictionary:
	return LoadoutsScript.for_archetype(archetype_id, minor)

## Combat.apply_hit_to's entry point (BaseNPC.take_hit, with Combat recording the harm)
func take_combat_hit(result: Dictionary, attacker) -> Dictionary:
	return super.take_combat_hit(result, attacker)

## A generic dies like anyone (any adult can, lead's ruling); its instance remembers how
func die(cause: String = "unknown", killer: String = "unknown"):
	var was_alive = is_alive
	await super.die(cause, killer)
	var manager = _manager()
	if was_alive and manager and manager.has_method("note_death"):
		manager.note_death(npc_id, cause, killer)

## Promoted or demoted: switch memory (own collection vs residue-only layers) and personality
func on_tier_changed() -> void:
	refresh_from_instance()
	var manager = _manager()
	if manager == null or rag_memory == null or not _is_initialized:
		return
	var inst = manager.get_instance(npc_id)
	var use_db = manager.wants_chroma(npc_id)
	rag_memory.memory_cache.clear()
	await rag_memory.initialize(npc_id, null, use_db)
	# Seed memory with what the instance carries (all layers when promoted, the residue when demoted)
	for layer in inst.layers:
		await rag_memory.store({"text": layer.text, "event_type": "generic_layer", "importance": layer.importance,
			"layer_kind": layer.kind}, "%s_layer_%s" % [npc_id, str(layer.get("tag", layer.text)).md5_text().substr(0, 10)], true)
