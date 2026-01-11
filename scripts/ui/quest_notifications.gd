extends CanvasLayer
## Quest Notification System - Shows popups for quest events
## Displays non-intrusive notifications when quests are discovered, objectives completed, etc.

@onready var notification_container: VBoxContainer = $NotificationContainer

# Notification queue to prevent overlapping
var notification_queue: Array = []
var is_showing: bool = false

# Notification types with colors
const NOTIFICATION_COLORS = {
	"quest_discovered": Color(0.94, 0.75, 0.25, 1.0),  # Gold
	"objective_complete": Color(0.4, 0.8, 0.4, 1.0),   # Green
	"quest_complete": Color(0.3, 0.9, 0.3, 1.0),       # Bright green
	"quest_failed": Color(0.9, 0.3, 0.3, 1.0)          # Red
}

# Display duration
const NOTIFICATION_DURATION = 3.0
const FADE_DURATION = 0.3

func _ready():
	# Set layer high to appear above game
	layer = 15

	# Connect to QuestManager signals
	if QuestManager:
		if QuestManager.has_signal("quest_discovered"):
			QuestManager.quest_discovered.connect(_on_quest_discovered)
		if QuestManager.has_signal("quest_objective_completed"):
			QuestManager.quest_objective_completed.connect(_on_objective_completed)
		if QuestManager.has_signal("quest_completed"):
			QuestManager.quest_completed.connect(_on_quest_completed)
		if QuestManager.has_signal("quest_failed"):
			QuestManager.quest_failed.connect(_on_quest_failed)

func _on_quest_discovered(quest_id: String):
	var quest = QuestManager.get_quest(quest_id) if QuestManager else null
	var title = quest.title if quest else quest_id
	var is_main = quest.is_main_quest if quest else false

	var prefix = "[MAIN QUEST]" if is_main else "[QUEST]"
	_queue_notification("%s %s" % [prefix, title], "New quest discovered!", "quest_discovered")

func _on_objective_completed(quest_id: String, objective_id: String):
	var quest = QuestManager.get_quest(quest_id) if QuestManager else null
	if not quest:
		return

	# Find the objective
	var obj_desc = objective_id
	for obj in quest.objectives:
		if obj.objective_id == objective_id:
			obj_desc = obj.description
			break

	_queue_notification("Objective Complete", obj_desc, "objective_complete")

func _on_quest_completed(quest_id: String, ending: String):
	var quest = QuestManager.get_quest(quest_id) if QuestManager else null
	var title = quest.title if quest else quest_id

	var ending_text = ""
	if quest and quest.possible_endings.has(ending):
		ending_text = quest.possible_endings[ending]

	if ending_text.is_empty():
		_queue_notification("Quest Complete!", title, "quest_complete")
	else:
		_queue_notification("Quest Complete!", "%s\n%s" % [title, ending_text], "quest_complete")

func _on_quest_failed(quest_id: String, reason: String):
	var quest = QuestManager.get_quest(quest_id) if QuestManager else null
	var title = quest.title if quest else quest_id

	if reason.is_empty():
		_queue_notification("Quest Failed", title, "quest_failed")
	else:
		_queue_notification("Quest Failed", "%s - %s" % [title, reason], "quest_failed")

func _queue_notification(title: String, message: String, type: String):
	notification_queue.append({
		"title": title,
		"message": message,
		"type": type
	})

	if not is_showing:
		_show_next_notification()

func _show_next_notification():
	if notification_queue.is_empty():
		is_showing = false
		return

	is_showing = true
	var data = notification_queue.pop_front()

	# Create notification panel
	var panel = _create_notification_panel(data.title, data.message, data.type)
	notification_container.add_child(panel)

	# Animate in
	panel.modulate.a = 0
	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, FADE_DURATION)

	# Wait, then fade out
	await get_tree().create_timer(NOTIFICATION_DURATION).timeout

	var fade_tween = create_tween()
	fade_tween.tween_property(panel, "modulate:a", 0.0, FADE_DURATION)
	await fade_tween.finished

	panel.queue_free()

	# Show next in queue
	_show_next_notification()

func _create_notification_panel(title: String, message: String, type: String) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(350, 0)

	# Create stylebox
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_width_left = 4
	style.border_color = NOTIFICATION_COLORS.get(type, Color.WHITE)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	# Content container
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Title
	var title_label = Label.new()
	title_label.text = title
	title_label.add_theme_color_override("font_color", NOTIFICATION_COLORS.get(type, Color.WHITE))
	title_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title_label)

	# Message
	var msg_label = Label.new()
	msg_label.text = message
	msg_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	msg_label.add_theme_font_size_override("font_size", 13)
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(msg_label)

	return panel

## Show a custom notification (for external use)
func show_notification(title: String, message: String, color: Color = Color.WHITE):
	var panel = _create_notification_panel(title, message, "custom")

	# Override color
	var style = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style.border_color = color

	notification_container.add_child(panel)

	panel.modulate.a = 0
	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, FADE_DURATION)

	await get_tree().create_timer(NOTIFICATION_DURATION).timeout

	var fade_tween = create_tween()
	fade_tween.tween_property(panel, "modulate:a", 0.0, FADE_DURATION)
	await fade_tween.finished

	panel.queue_free()
