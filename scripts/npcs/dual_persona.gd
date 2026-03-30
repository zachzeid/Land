extends Node
class_name DualPersona
## DualPersona - Enables NPCs to have a hidden second personality layer
##
## Designed for Mira (The Boss) but generalizable to any NPC with a secret identity.
## The NPC has two personality layers:
##   Layer 1 (Cover): default behavior, what the world sees
##   Layer 2 (Hidden): true personality, activated by a world flag
##
## The agent loop uses Hidden reasoning for decisions, but wraps public actions
## in Cover behavior. When the reveal flag is set, all behavior switches to Hidden.
##
## Usage: Attach as child of a BaseNPC node. Configure via exports.

## The world flag that triggers the reveal
@export var reveal_flag: String = ""

## The hidden persona's core identity (injected into Claude prompt after reveal)
@export_multiline var hidden_identity: String = ""

## The hidden persona's identity anchors
@export var hidden_anchors: Array[String] = []

## The hidden persona's speaking style (replaces cover style after reveal)
@export var hidden_speaking_style: String = ""

## Whether the hidden persona has been revealed
var is_revealed: bool = false

## Reference to parent NPC
var npc: Node = null

func _ready():
	npc = get_parent()
	EventBus.world_flag_changed.connect(_on_flag_changed)

	# Check if already revealed (from save game)
	if reveal_flag != "" and WorldState.get_world_flag(reveal_flag):
		_activate_hidden_persona()

func _on_flag_changed(flag_name: String, _old_value, new_value):
	if flag_name == reveal_flag and new_value == true:
		_activate_hidden_persona()

func _activate_hidden_persona():
	if is_revealed:
		return

	is_revealed = true
	print("[DualPersona:%s] Hidden persona ACTIVATED — the mask is off" % _get_npc_name())

	# Update the NPC's system prompt to include the hidden identity
	if npc and npc.get("system_prompt"):
		var reveal_section = _build_reveal_context()
		npc.system_prompt = npc.system_prompt + "\n\n" + reveal_section

## Build the context injection for the revealed persona
func _build_reveal_context() -> String:
	var context = "\n## ⚠️ YOUR TRUE IDENTITY HAS BEEN REVEALED ⚠️\n"
	context += "The player now knows who you really are.\n\n"

	if hidden_identity != "":
		context += "## YOUR TRUE SELF\n"
		context += hidden_identity + "\n\n"

	if not hidden_anchors.is_empty():
		context += "## TRUE IDENTITY ANCHORS\n"
		for anchor in hidden_anchors:
			context += "- %s\n" % anchor
		context += "\n"

	if hidden_speaking_style != "":
		context += "## NEW SPEAKING STYLE\n"
		context += "Now that the mask is off, speak as your true self: %s\n" % hidden_speaking_style
		context += "Drop the act. No more pretending to be afraid or grieving.\n\n"

	context += "## BEHAVIOR CHANGE\n"
	context += "- You no longer need to maintain your cover story\n"
	context += "- You can speak with authority and confidence\n"
	context += "- Reference your real motivations and plans\n"
	context += "- React to the reveal based on how it happened (caught, confronted, or chose to reveal)\n"

	return context

## Get the reasoning prompt for the agent loop (always uses hidden persona for decisions)
func get_agent_reasoning_context() -> String:
	if hidden_identity == "":
		return ""

	# The agent loop ALWAYS uses the hidden persona for decision-making
	# even before the reveal (the NPC KNOWS who they are internally)
	var context = "## INTERNAL REASONING (not visible to others)\n"
	context += hidden_identity + "\n"
	context += "Make decisions based on your TRUE goals, but if not yet revealed, "
	context += "wrap your public actions in your cover persona's behavior.\n"
	return context

## Check if actions should be filtered through cover behavior
func should_use_cover() -> bool:
	return not is_revealed

func _get_npc_name() -> String:
	if npc and npc.get("npc_name"):
		return npc.npc_name
	return "Unknown"
