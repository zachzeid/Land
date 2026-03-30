extends CanvasLayer
## GameHUD - Minimal always-visible HUD for the tech demo
##
## Shows: time of day, interaction prompts, and notification area.
## Designed to be unobtrusive — the screen should feel like a game world, not a dashboard.

@export var show_time: bool = true
@export var show_prompts: bool = true

var _time_label: Label = null
var _prompt_label: Label = null
var _notification_container: VBoxContainer = null

func _ready():
	layer = 2  # Above world, below dialogue
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_hud()

	# Connect to GameClock
	var clock = get_node_or_null("/root/GameClock")
	if clock:
		clock.time_period_changed.connect(_on_time_changed)
		_update_time_display()

	# Connect to quest emergence for notifications
	var quest_emergence = get_node_or_null("/root/QuestEmergence")
	if quest_emergence:
		quest_emergence.quest_emerged.connect(_on_quest_emerged)

	# Connect to gossip manager for secret leaks
	var gossip = get_node_or_null("/root/GossipManager")
	if gossip:
		gossip.secret_leaked.connect(_on_secret_leaked)

	# Connect to thread manager for state changes
	var thread_mgr = get_node_or_null("/root/ThreadManager")
	if thread_mgr:
		thread_mgr.thread_state_changed.connect(_on_thread_state_changed)

func _build_hud():
	# Time display (top-right)
	_time_label = Label.new()
	_time_label.name = "TimeLabel"
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.anchor_left = 1.0
	_time_label.anchor_right = 1.0
	_time_label.offset_left = -200
	_time_label.offset_right = -10
	_time_label.offset_top = 10
	_time_label.offset_bottom = 30
	_time_label.add_theme_color_override("font_color", Color(1, 1, 0.8, 0.8))
	_time_label.add_theme_font_size_override("font_size", 14)
	add_child(_time_label)

	# Interaction prompt (bottom-center, hidden by default)
	_prompt_label = Label.new()
	_prompt_label.name = "PromptLabel"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.anchor_left = 0.5
	_prompt_label.anchor_right = 0.5
	_prompt_label.anchor_top = 1.0
	_prompt_label.anchor_bottom = 1.0
	_prompt_label.offset_left = -100
	_prompt_label.offset_right = 100
	_prompt_label.offset_top = -60
	_prompt_label.offset_bottom = -40
	_prompt_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_prompt_label.add_theme_constant_override("outline_size", 3)
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.visible = false
	add_child(_prompt_label)

	# Notification area (top-left)
	_notification_container = VBoxContainer.new()
	_notification_container.name = "Notifications"
	_notification_container.offset_left = 10
	_notification_container.offset_top = 10
	_notification_container.offset_right = 350
	_notification_container.offset_bottom = 200
	add_child(_notification_container)

func _update_time_display():
	var clock = get_node_or_null("/root/GameClock")
	if clock and _time_label:
		_time_label.text = clock.get_time_string()

func _on_time_changed(_new_period: String, _old_period: String):
	_update_time_display()

## Show an interaction prompt (called by interaction areas)
func show_prompt(text: String):
	if _prompt_label:
		_prompt_label.text = text
		_prompt_label.visible = true

## Hide the interaction prompt
func hide_prompt():
	if _prompt_label:
		_prompt_label.visible = false

## Show a notification toast
func show_notification(text: String, color: Color = Color(1, 1, 1, 1), duration: float = 4.0):
	if _notification_container == null:
		return

	var label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 2)
	_notification_container.add_child(label)

	# Fade out after duration
	var tween = create_tween()
	tween.tween_interval(duration)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)

## React to quest emergence
func _on_quest_emerged(quest_id: String, _template: String, _thread_id: String):
	show_notification("New quest available", Color(1, 0.85, 0.2), 5.0)

## React to secret leaked
func _on_secret_leaked(from_npc: String, to_npc: String, _content: String):
	# Subtle notification — player shouldn't always know secrets are spreading
	# Only show if player is nearby
	var player = get_tree().get_first_node_in_group("player")
	if player:
		for npc in get_tree().get_nodes_in_group("npcs"):
			if npc.get("npc_id") == from_npc and npc.global_position.distance_to(player.global_position) < 200:
				show_notification("You overhear hushed whispers...", Color(0.7, 0.7, 1.0), 3.0)
				break

## React to thread state changes
func _on_thread_state_changed(thread_id: String, _old_state: String, new_state: String):
	if new_state == "crisis":
		var thread_mgr = get_node_or_null("/root/ThreadManager")
		if thread_mgr and thread_id in thread_mgr.threads:
			var name = thread_mgr.threads[thread_id].name
			show_notification("Something is reaching a tipping point...", Color(1, 0.4, 0.4), 5.0)
