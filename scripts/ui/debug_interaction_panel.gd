extends Control
# Debug panel for testing NPC interactions
# Shows dimension values and provides buttons to trigger different interaction types

@onready var trust_label = $VBoxContainer/Dimensions/TrustLabel
@onready var respect_label = $VBoxContainer/Dimensions/RespectLabel
@onready var affection_label = $VBoxContainer/Dimensions/AffectionLabel
@onready var fear_label = $VBoxContainer/Dimensions/FearLabel
@onready var familiarity_label = $VBoxContainer/Dimensions/FamiliarityLabel

var current_npc: Node = null

func _ready():
	hide()  # Hidden by default
	
	# Connect all interaction buttons
	$VBoxContainer/PositiveInteractions/QuestButton.pressed.connect(_on_quest_completed)
	$VBoxContainer/PositiveInteractions/GiftButton.pressed.connect(_on_gift_given)
	$VBoxContainer/PositiveInteractions/SupportButton.pressed.connect(_on_emotional_support)
	$VBoxContainer/PositiveInteractions/DangerButton.pressed.connect(_on_shared_danger)
	
	$VBoxContainer/NegativeInteractions/BetrayalButton.pressed.connect(_on_betrayal)
	$VBoxContainer/NegativeInteractions/InsultButton.pressed.connect(_on_insult)
	$VBoxContainer/NegativeInteractions/TheftButton.pressed.connect(_on_theft_witnessed)
	
	$VBoxContainer/RomanticInteractions/GestureButton.pressed.connect(_on_romantic_gesture)
	$VBoxContainer/RomanticInteractions/ConfessionButton.pressed.connect(_on_romantic_confession)
	
	$VBoxContainer/CloseButton.pressed.connect(_on_close)

func set_npc(npc: Node):
	current_npc = npc
	if npc:
		_update_dimensions()
		show()

func _update_dimensions():
	if not current_npc:
		return
	
	trust_label.text = "Trust: %d" % current_npc.relationship_trust
	respect_label.text = "Respect: %d" % current_npc.relationship_respect
	affection_label.text = "Affection: %d" % current_npc.relationship_affection
	fear_label.text = "Fear: %d" % current_npc.relationship_fear
	familiarity_label.text = "Familiarity: %d" % current_npc.relationship_familiarity

# Positive Interactions
func _on_quest_completed():
	if current_npc:
		await current_npc.record_interaction("quest_completed", {
			"description": "Player helped complete an important quest",
			"importance": 9
		})
		_update_dimensions()
		print("[Debug] Quest completed - Trust +15, Respect +10, Affection +8")

func _on_gift_given():
	if current_npc:
		await current_npc.record_interaction("gift_received", {
			"description": "Player gave a thoughtful gift",
			"importance": 8,
			"thoughtfulness": "high"
		})
		_update_dimensions()
		print("[Debug] Thoughtful gift given - Affection +15, Trust +8")

func _on_emotional_support():
	if current_npc:
		await current_npc.record_interaction("emotional_support", {
			"description": "Player listened without judgment",
			"importance": 7
		})
		_update_dimensions()
		print("[Debug] Emotional support - Trust +8, Affection +10")

func _on_shared_danger():
	if current_npc:
		await current_npc.record_interaction("shared_danger", {
			"description": "Fought together in dangerous situation",
			"importance": 10
		})
		_update_dimensions()
		print("[Debug] Shared danger - Trust +20, Respect +15, Affection +10, Fear -10")

# Negative Interactions
func _on_betrayal():
	if current_npc:
		await current_npc.record_interaction("betrayal", {
			"description": "Player broke trust in serious way",
			"importance": 10
		})
		_update_dimensions()
		print("[Debug] Betrayal - Trust -30, Respect -20, Affection -25")

func _on_insult():
	if current_npc:
		await current_npc.record_interaction("insult", {
			"description": "Player insulted the NPC",
			"importance": 6
		})
		_update_dimensions()
		print("[Debug] Insult - Respect -15, Affection -10")

func _on_theft_witnessed():
	if current_npc:
		await current_npc.record_interaction("theft_witnessed", {
			"description": "NPC saw player stealing",
			"importance": 8
		})
		_update_dimensions()
		print("[Debug] Theft witnessed - Trust -20, Fear +10")

# Romantic Interactions
func _on_romantic_gesture():
	if current_npc:
		await current_npc.record_interaction("romantic_gesture", {
			"description": "Player made romantic gesture",
			"importance": 8
		})
		_update_dimensions()
		print("[Debug] Romantic gesture - Affection +15, Trust +10")

func _on_romantic_confession():
	if current_npc:
		await current_npc.record_interaction("romantic_confession", {
			"description": "Player confessed feelings (reciprocated)",
			"importance": 10,
			"reciprocated": true
		})
		_update_dimensions()
		print("[Debug] Romantic confession - Affection +30, Trust +15")

func _on_close():
	hide()
	current_npc = null

func _input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		_on_close()
		get_viewport().set_input_as_handled()
