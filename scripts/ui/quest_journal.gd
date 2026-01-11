extends CanvasLayer
## Quest Journal UI - Player-facing quest tracking interface
## Toggle with J key, shows active/completed/discovered quests with objectives and hints
## Pauses game while open, uses CanvasLayer 10 for proper UI stacking

@onready var panel: Panel = $Panel
@onready var close_button: Button = $Panel/Header/CloseButton
@onready var active_tab: Button = $Panel/TabBar/ActiveTab
@onready var completed_tab: Button = $Panel/TabBar/CompletedTab
@onready var discovered_tab: Button = $Panel/TabBar/DiscoveredTab
@onready var quest_list: VBoxContainer = $Panel/Content/QuestListScroll/QuestList
@onready var quest_title: Label = $Panel/Content/DetailScroll/DetailContent/QuestTitle
@onready var quest_type_badge: Label = $Panel/Content/DetailScroll/DetailContent/QuestTypeBadge
@onready var quest_description: RichTextLabel = $Panel/Content/DetailScroll/DetailContent/QuestDescription
@onready var objectives_container: VBoxContainer = $Panel/Content/DetailScroll/DetailContent/ObjectivesContainer
@onready var no_quest_label: Label = $Panel/Content/DetailScroll/DetailContent/NoQuestLabel

enum Tab { ACTIVE, COMPLETED, DISCOVERED }

var is_open: bool = false
var current_tab: Tab = Tab.ACTIVE
var selected_quest_id: String = ""
var quest_buttons: Dictionary = {}  # quest_id -> Button

# Colors
const COLOR_ACTIVE_TAB = Color(0.94, 0.75, 0.25, 1.0)  # Gold
const COLOR_INACTIVE_TAB = Color(0.5, 0.5, 0.5, 1.0)  # Gray
const COLOR_MAIN_QUEST = Color(0.94, 0.75, 0.25, 1.0)  # Gold star
const COLOR_SIDE_QUEST = Color(0.7, 0.7, 0.7, 1.0)  # Gray
const COLOR_COMPLETE = Color(0.4, 0.8, 0.4, 1.0)  # Green
const COLOR_INCOMPLETE = Color(0.6, 0.6, 0.6, 1.0)  # Gray
const COLOR_HINT = Color(0.6, 0.7, 0.8, 1.0)  # Light blue-gray

func _ready():
	# Set layer for proper UI stacking
	layer = 10

	# Start hidden
	panel.visible = false

	# Process while paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Connect buttons
	close_button.pressed.connect(_close_journal)
	active_tab.pressed.connect(func(): _switch_tab(Tab.ACTIVE))
	completed_tab.pressed.connect(func(): _switch_tab(Tab.COMPLETED))
	discovered_tab.pressed.connect(func(): _switch_tab(Tab.DISCOVERED))

	# Connect to quest events
	if QuestManager:
		if QuestManager.has_signal("quest_available"):
			QuestManager.quest_available.connect(_on_quest_changed)
		if QuestManager.has_signal("quest_discovered"):
			QuestManager.quest_discovered.connect(_on_quest_changed)
		if QuestManager.has_signal("quest_completed"):
			QuestManager.quest_completed.connect(_on_quest_completed)
		if QuestManager.has_signal("quest_objective_completed"):
			QuestManager.quest_objective_completed.connect(_on_objective_completed)

func _input(event: InputEvent):
	if event.is_action_pressed("open_journal"):
		# Don't open during dialogue
		if _is_in_dialogue():
			return
		_toggle_journal()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and is_open:
		_close_journal()
		get_viewport().set_input_as_handled()

func _toggle_journal():
	if is_open:
		_close_journal()
	else:
		_open_journal()

func _open_journal():
	is_open = true
	panel.visible = true
	get_tree().paused = true
	_switch_tab(current_tab)
	_refresh_quest_list()

func _close_journal():
	is_open = false
	panel.visible = false
	get_tree().paused = false

func _is_in_dialogue() -> bool:
	# Check if DialogueManager is in an active conversation
	if DialogueManager and "is_conversation_active" in DialogueManager:
		return DialogueManager.is_conversation_active
	# Fallback: check if dialogue UI is visible
	var dialogue_ui = get_tree().get_first_node_in_group("dialogue_ui")
	if dialogue_ui and dialogue_ui.visible:
		return true
	return false

func _switch_tab(tab: Tab):
	current_tab = tab

	# Update tab button colors
	active_tab.modulate = COLOR_ACTIVE_TAB if tab == Tab.ACTIVE else COLOR_INACTIVE_TAB
	completed_tab.modulate = COLOR_ACTIVE_TAB if tab == Tab.COMPLETED else COLOR_INACTIVE_TAB
	discovered_tab.modulate = COLOR_ACTIVE_TAB if tab == Tab.DISCOVERED else COLOR_INACTIVE_TAB

	_refresh_quest_list()

func _refresh_quest_list():
	# Clear existing list
	for child in quest_list.get_children():
		child.queue_free()
	quest_buttons.clear()

	# Get quests for current tab
	var quest_ids: Array = []
	match current_tab:
		Tab.ACTIVE:
			quest_ids = QuestManager.get_active_quest_ids() if QuestManager else []
		Tab.COMPLETED:
			quest_ids = QuestManager.get_completed_quest_ids() if QuestManager else []
		Tab.DISCOVERED:
			quest_ids = QuestManager.get_available_quest_ids() if QuestManager else []

	# Update tab counts
	_update_tab_counts()

	if quest_ids.is_empty():
		_show_empty_state()
		return

	# Sort by priority (main quests first)
	var quests = []
	for quest_id in quest_ids:
		var quest = QuestManager.get_quest(quest_id)
		if quest:
			quests.append(quest)
	quests.sort_custom(func(a, b):
		if a.is_main_quest != b.is_main_quest:
			return a.is_main_quest  # Main quests first
		return a.priority > b.priority
	)

	# Create buttons for each quest
	for quest in quests:
		var btn = _create_quest_button(quest)
		quest_list.add_child(btn)
		quest_buttons[quest.quest_id] = btn

	# Select first quest if none selected
	if selected_quest_id.is_empty() or selected_quest_id not in quest_buttons:
		if not quests.is_empty():
			_select_quest(quests[0].quest_id)
		else:
			_clear_detail_panel()
	else:
		_select_quest(selected_quest_id)

func _create_quest_button(quest) -> Button:
	var btn = Button.new()
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Quest title with main quest star
	var title = quest.title if quest.title else quest.quest_id
	if quest.is_main_quest:
		btn.text = "  %s" % title
	else:
		btn.text = "  %s" % title

	# Add main quest indicator
	if quest.is_main_quest:
		btn.icon = null  # Could add star icon here
		btn.text = "  %s" % title

	btn.pressed.connect(func(): _select_quest(quest.quest_id))

	return btn

func _select_quest(quest_id: String):
	selected_quest_id = quest_id

	# Update button highlighting
	for qid in quest_buttons:
		var btn = quest_buttons[qid]
		btn.button_pressed = (qid == quest_id)

	# Show quest details
	_show_quest_details(quest_id)

func _show_quest_details(quest_id: String):
	var quest = QuestManager.get_quest(quest_id) if QuestManager else null
	if not quest:
		_clear_detail_panel()
		return

	no_quest_label.visible = false
	quest_title.visible = true
	quest_type_badge.visible = true
	quest_description.visible = true
	objectives_container.visible = true

	# Title
	quest_title.text = quest.title if quest.title else quest.quest_id

	# Type badge
	if quest.is_main_quest:
		quest_type_badge.text = "[MAIN QUEST]"
		quest_type_badge.modulate = COLOR_MAIN_QUEST
	else:
		quest_type_badge.text = "[SIDE QUEST]"
		quest_type_badge.modulate = COLOR_SIDE_QUEST

	# Description
	quest_description.text = quest.description if quest.description else "No description available."

	# Clear and rebuild objectives
	for child in objectives_container.get_children():
		if child.name != "ObjectivesHeader":
			child.queue_free()

	# Add objectives
	if "objectives" in quest and quest.objectives.size() > 0:
		for obj in quest.objectives:
			_add_objective_display(obj, quest)

func _add_objective_display(objective, quest):
	var container = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Objective line with checkbox
	var obj_line = HBoxContainer.new()
	obj_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var checkbox = Label.new()
	if objective.is_completed:
		checkbox.text = ""
		checkbox.modulate = COLOR_COMPLETE
	else:
		checkbox.text = ""
		checkbox.modulate = COLOR_INCOMPLETE
	obj_line.add_child(checkbox)

	var obj_text = Label.new()
	obj_text.text = " " + objective.description
	obj_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if objective.is_completed:
		obj_text.modulate = COLOR_COMPLETE
	obj_line.add_child(obj_text)

	container.add_child(obj_line)

	# Add hint line if not completed
	if not objective.is_completed:
		var hint = _generate_objective_hint(objective, quest)
		if not hint.is_empty():
			var hint_label = Label.new()
			hint_label.text = "   %s" % hint
			hint_label.modulate = COLOR_HINT
			hint_label.add_theme_font_size_override("font_size", 12)
			container.add_child(hint_label)

	objectives_container.add_child(container)

func _generate_objective_hint(objective, quest) -> String:
	# Relationship-based objective
	if "complete_on_relationship" in objective and objective.complete_on_relationship:
		var rel_data = objective.complete_on_relationship
		for npc_id in rel_data:
			var target = rel_data[npc_id]
			var current = _get_npc_trust(npc_id)
			var progress = _make_progress_bar(current, target)
			var npc_name = _get_npc_display_name(npc_id)
			return "Trust with %s: %s %d/%d" % [npc_name, progress, int(current), int(target)]

	# Topic-based objective
	if "complete_on_topics" in objective and objective.complete_on_topics.size() > 0:
		var topics = objective.complete_on_topics
		var npc_hint = ""
		if "requires_npc" in objective and objective.requires_npc:
			npc_hint = " with %s" % _get_npc_display_name(objective.requires_npc)
		return "Discuss%s: \"%s\"" % [npc_hint, "\", \"".join(topics)]

	# Intent-based objective
	if "complete_on_intent" in objective and objective.complete_on_intent:
		var intent = objective.complete_on_intent
		var npc_hint = ""
		if "requires_npc" in objective and objective.requires_npc:
			npc_hint = " from %s" % _get_npc_display_name(objective.requires_npc)
		match intent:
			"revelation":
				return "Uncover a secret%s" % npc_hint
			"confession":
				return "Get a confession%s" % npc_hint
			"secret_shared":
				return "Learn a secret%s" % npc_hint
			_:
				return "Trigger: %s%s" % [intent, npc_hint]

	# Location-based objective
	if "complete_on_location" in objective and objective.complete_on_location:
		return "Travel to: %s" % objective.complete_on_location.replace("_", " ").capitalize()

	# Flag-based objective
	if "complete_on_flag" in objective and objective.complete_on_flag:
		return "Requirement not yet met"

	return ""

func _make_progress_bar(current: float, target: float) -> String:
	var filled = int((current / target) * 10)
	filled = clamp(filled, 0, 10)
	var empty = 10 - filled
	return "" + "".repeat(empty)

func _get_npc_trust(npc_id: String) -> float:
	var npcs = get_tree().get_nodes_in_group("npcs")
	for npc in npcs:
		if "npc_id" in npc and npc.npc_id == npc_id:
			if "relationship_trust" in npc:
				return npc.relationship_trust
	return 0.0

func _get_npc_display_name(npc_id: String) -> String:
	var npcs = get_tree().get_nodes_in_group("npcs")
	for npc in npcs:
		if "npc_id" in npc and npc.npc_id == npc_id:
			if "display_name" in npc:
				return npc.display_name
			if "npc_name" in npc:
				return npc.npc_name
	# Fallback: extract name from ID
	return npc_id.split("_")[0].capitalize()

func _clear_detail_panel():
	quest_title.visible = false
	quest_type_badge.visible = false
	quest_description.visible = false
	objectives_container.visible = false
	no_quest_label.visible = true

func _show_empty_state():
	_clear_detail_panel()
	match current_tab:
		Tab.ACTIVE:
			no_quest_label.text = "No active quests.\n\nTalk to the villagers to discover new quests."
		Tab.COMPLETED:
			no_quest_label.text = "No completed quests yet.\n\nComplete quests to see them here."
		Tab.DISCOVERED:
			no_quest_label.text = "No discovered quests.\n\nExplore and talk to NPCs to find new quests."

func _update_tab_counts():
	var active_count = QuestManager.get_active_quest_ids().size() if QuestManager else 0
	var completed_count = QuestManager.get_completed_quest_ids().size() if QuestManager else 0
	var discovered_count = QuestManager.get_available_quest_ids().size() if QuestManager else 0

	active_tab.text = "Active (%d)" % active_count
	completed_tab.text = "Completed (%d)" % completed_count
	discovered_tab.text = "Discovered (%d)" % discovered_count

# Event handlers
func _on_quest_changed(_quest_id: String):
	if is_open:
		_refresh_quest_list()

func _on_quest_completed(_quest_id: String, _ending: String):
	if is_open:
		_refresh_quest_list()

func _on_objective_completed(_quest_id: String, _objective_id: String):
	if is_open and selected_quest_id == _quest_id:
		_show_quest_details(_quest_id)
