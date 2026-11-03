extends CanvasLayer
## InventoryPanel - the pack, equipment and coin, with the skills page beside it (docs/PLAYER_SYSTEMS.md §6, §8)
## The inventory action (I) opens it over the world (PlayerUI decides when it may), I or Esc closes it.
## It pauses the world like the menu. Each item shows its quality, durability, maker and whether it
## was stolen; weapons, armour and tools can be equipped and unequipped. Coin is shown as crowns,
## gold, silver and copper (Inventory holds copper). Everything goes through the Inventory contract

const UI = preload("res://scripts/ui/player_ui.gd")
const SkillsPage = preload("res://scripts/ui/skills_page.gd")
const Camp = preload("res://scripts/world/camp.gd")
## Equipment slots (spec §6) and the slot an item kind goes to when its definition names none
const SLOTS = ["main_hand", "off_hand", "body", "head", "tool"]  # Inventory's equipment slots
const SLOT_NAMES = {"main_hand": "Main hand", "off_hand": "Off hand", "body": "Body", "head": "Head", "tool": "Tool"}
const KIND_SLOT = {"weapon": "main_hand", "armour": "body", "tool": "tool"}

## Injectable for tests; the Inventory autoload otherwise
var inventory: Node = null
var is_open: bool = false
var tab: String = "pack"   # pack | skills
var skills_page: VBoxContainer
var _was_paused: bool = false
var _coin: Label
var _equipped: VBoxContainer
var _items: VBoxContainer
var _pack_view: Control
var _message: Label

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	var inv = _inventory()
	if inv and inv.has_signal("changed"):
		inv.changed.connect(_on_changed)

func _on_changed() -> void:
	if is_open:
		refresh()

func _build() -> void:
	var parts = UI.centred_frame(self, Vector2(640, 460))
	var vbox: VBoxContainer = parts[1]
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vbox.add_child(top)
	var title = UI.label("Your pack", 24, UI.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UI.button("Pack", func(): show_tab("pack"), 90))
	top.add_child(UI.button("Skills", func(): show_tab("skills"), 90))
	_pack_view = VBoxContainer.new()
	_pack_view.name = "Pack"
	_pack_view.add_theme_constant_override("separation", 8)
	vbox.add_child(_pack_view)
	_coin = UI.label("", 16, UI.GOLD)
	_coin.name = "Coin"
	_pack_view.add_child(_coin)
	_pack_view.add_child(UI.label("Equipped", 15, UI.GOLD))
	_equipped = VBoxContainer.new()
	_equipped.name = "Equipped"
	_pack_view.add_child(_equipped)
	_pack_view.add_child(UI.label("Carried", 15, UI.GOLD))
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pack_view.add_child(scroll)
	_items = VBoxContainer.new()
	_items.name = "Items"
	_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_items)
	skills_page = SkillsPage.new()
	skills_page.visible = false
	vbox.add_child(skills_page)
	_message = UI.label("", 13, UI.FAINT)
	vbox.add_child(_message)
	var bottom = HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(UI.label("I or Esc to close   ", 12, UI.FAINT))
	bottom.add_child(UI.button("Close", close))
	vbox.add_child(bottom)

func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") or (event.is_action_pressed("inventory") and not event.is_echo()):
		get_viewport().set_input_as_handled()
		close()

func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_message.text = ""
	show_tab(tab)

func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = _was_paused

func show_tab(which: String) -> void:
	tab = which
	_pack_view.visible = which == "pack"
	skills_page.visible = which == "skills"
	refresh()

func refresh() -> void:
	if tab == "skills":
		skills_page.refresh()
		return
	var inv = _inventory()
	UI.clear(_equipped)
	UI.clear(_items)
	if inv == null:
		_coin.text = ""
		return
	_coin.text = "Coin: " + UI.format_coin(int(inv.get_coin()))
	for slot in SLOTS:
		var row = HBoxContainer.new()
		row.add_child(_cell(SLOT_NAMES[slot], 110, UI.FAINT))
		var worn: Dictionary = inv.get_equipped(slot)
		if worn.is_empty() or str(worn.get("id", "")) == "":
			row.add_child(_cell("nothing", 300, UI.FAINT))
		else:
			row.add_child(_cell(describe(worn, inv), 380))
			row.add_child(UI.button("Unequip", unequip.bind(slot), 90))
		_equipped.add_child(row)
	var items: Array = inv.get_items()
	if items.is_empty():
		_items.add_child(UI.label("You carry nothing.", 14, UI.FAINT))
	for item in items:
		if not item is Dictionary or str(item.get("slot", "")) != "":
			continue  # worn or held: listed under Equipped above
		var row = HBoxContainer.new()
		var line = _cell(describe(item, inv), 440)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(line)
		var slot = slot_for(item)
		if slot != "":
			if is_equipped(item):
				row.add_child(UI.button("Unequip", unequip.bind(slot), 90))
			else:
				row.add_child(UI.button("Equip", equip.bind(item, slot), 90))
		if "camp" in inv.get_item_def(str(item.get("id", ""))).get("tags", []):
			row.add_child(UI.button("Make camp", make_camp, 110))
		_items.add_child(row)

## "Iron knife ×2 · fine (72) · 18/40 · made by Bjorn · stolen"
static func describe(item: Dictionary, inv: Node = null) -> String:
	var id = str(item.get("id", ""))
	var parts: Array = [UI.item_name(id, inv) + (" ×%d" % int(item.get("qty", 1)) if int(item.get("qty", 1)) > 1 else "")]
	if item.has("quality"):
		parts.append("%s (%d)" % [quality_word(float(item.quality)), roundi(float(item.quality))])
	if float(item.get("max_durability", 0)) > 0:
		parts.append("%d/%d" % [roundi(float(item.get("durability", 0))), roundi(float(item.max_durability))])
		if float(item.get("durability", 0)) <= 0:
			parts.append("broken")
	var maker = str(item.get("maker", ""))
	if maker != "":
		parts.append("made by " + ("you" if maker == "player" else maker.capitalize()))
	var provenance = item.get("provenance", {})
	if provenance is Dictionary and provenance.get("stolen", false):
		parts.append("stolen")
	return " · ".join(parts)

static func quality_word(q: float) -> String:
	if q >= 90:
		return "masterwork"
	if q >= 70:
		return "fine"
	if q >= 45:
		return "sound"
	if q >= 20:
		return "plain"
	return "crude"

## The slot this item is worn in, "" for things that are only carried
func slot_for(item: Dictionary) -> String:
	var d = UI.item_def(str(item.get("id", "")), _inventory())
	if d.has("slot") and str(d.slot) in SLOTS:
		return str(d.slot)
	var tags: Array = d.get("tags", [])
	if "shield" in tags or "off_hand" in tags:
		return "off_hand"
	if str(d.get("kind", "")) == "armour":
		return "head" if "head" in tags else "body"
	return KIND_SLOT.get(str(d.get("kind", item.get("kind", ""))), "")

func is_equipped(item: Dictionary) -> bool:
	var inv = _inventory()
	var slot = slot_for(item)
	return inv != null and slot != "" and str(inv.get_equipped(slot).get("id", "")) == str(item.get("id", ""))

func equip(item: Dictionary, slot: String) -> bool:
	var inv = _inventory()
	var ok = inv != null and inv.equip(str(item.get("id", "")), slot)
	_message.text = "" if ok else "You cannot wear that there."
	refresh()
	return ok

## The contract has no unequip yet: Inventory.unequip(slot) when it exists, else equip("", slot)
func unequip(slot: String) -> bool:
	var inv = _inventory()
	if inv == null:
		return false
	var ok = inv.unequip(slot) if inv.has_method("unequip") else inv.equip("", slot)
	refresh()
	return bool(ok)

## Lay out the bedroll by a campfire where the player stands (camp.gd): wake here after a death
func make_camp() -> Dictionary:
	var player = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	var r: Dictionary = Camp.make_camp("", player.global_position if player is Node2D else Vector2.ZERO)
	_message.text = "You make camp. You will wake here." if r.ok else str(r.reason).capitalize() + "."
	refresh()
	return r

func get_coin_text() -> String:
	return _coin.text

func get_item_lines() -> Array:
	var out: Array = []
	for row in _items.get_children():
		for c in row.get_children():
			if c is Label:
				out.append(c.text)
	return out

func _cell(text: String, width: float, color: Color = UI.PARCHMENT) -> Label:
	var l = UI.label(text, 14, color)
	l.custom_minimum_size = Vector2(width, 0)
	return l

func _inventory() -> Node:
	return inventory if inventory else UI.autoload("Inventory")
