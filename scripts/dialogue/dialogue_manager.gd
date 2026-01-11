extends Node
# DialogueManager - Orchestrates NPC conversations and manages dialogue state

var active_conversations := {}
var conversation_history := {}

func _ready():
	print("DialogueManager initialized")

func start_conversation(npc_id: String, npc_node: Node):
	if active_conversations.has(npc_id):
		print("Conversation with %s already active" % npc_id)
		return
	
	active_conversations[npc_id] = {
		"npc_node": npc_node,
		"turn_count": 0,
		"started_at": Time.get_unix_time_from_system()
	}
	
	if not conversation_history.has(npc_id):
		conversation_history[npc_id] = []

func end_conversation(npc_id: String):
	if active_conversations.has(npc_id):
		active_conversations.erase(npc_id)

func add_to_history(npc_id: String, speaker: String, message: String):
	if not conversation_history.has(npc_id):
		conversation_history[npc_id] = []
	
	conversation_history[npc_id].append({
		"speaker": speaker,
		"message": message,
		"timestamp": Time.get_unix_time_from_system()
	})

func get_history(npc_id: String, limit: int = -1) -> Array:
	if not conversation_history.has(npc_id):
		return []
	
	var history = conversation_history[npc_id]
	if limit > 0 and history.size() > limit:
		return history.slice(history.size() - limit, history.size())
	return history

func clear_history(npc_id: String):
	if conversation_history.has(npc_id):
		conversation_history.erase(npc_id)
