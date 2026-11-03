extends CanvasLayer
## HUD - health and stamina bars, the derived level and brief hit feedback (docs/PLAYER_SYSTEMS.md §8)
## Reads PlayerStats through the contract getters every frame, so it shows the stub's fixed values
## and the real system's alike. Hit feedback comes from the health falling, whatever caused it (a
## blow, a fall, fire), so no other slice has to tell the HUD anything
## PlayerUI hides it during the opening card and the epilogue

const UI = preload("res://scripts/ui/player_ui.gd")
const FLASH_SECONDS = 0.35
const NOTE_SECONDS = 2.0

## Injectable for tests; the PlayerStats autoload otherwise
var stats: Node = null
var hit_flashes: int = 0
var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _health_text: Label
var _stamina_text: Label
var _level: Label
var _flash: ColorRect
var _note: Label
var _last_health: float = -1.0
var _flash_tween: Tween
var _note_tween: Tween

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")
	_build()
	refresh()

func _build() -> void:
	_flash = ColorRect.new()
	_flash.name = "HitFlash"
	_flash.color = Color(0.7, 0.05, 0.02, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)
	var box = PanelContainer.new()
	box.name = "Bars"
	var style = UI.frame_style()
	style.bg_color.a = 0.75
	style.set_border_width_all(2)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", style)
	box.position = Vector2(20, 20)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	box.add_child(vbox)
	_level = UI.label("Level 0", 13, UI.GOLD)
	vbox.add_child(_level)
	var health = _bar(Color(0.68, 0.14, 0.1))
	_health_bar = health[0]
	_health_text = health[1]
	vbox.add_child(health[2])
	var stamina = _bar(Color(0.55, 0.62, 0.2))
	_stamina_bar = stamina[0]
	_stamina_text = stamina[1]
	vbox.add_child(stamina[2])
	_note = UI.label("", 14)
	_note.name = "Note"
	_note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_note.add_theme_constant_override("outline_size", 3)
	_note.position = Vector2(24, 96)
	_note.visible = false
	add_child(_note)

## [bar, its number, the row holding both]
func _bar(fill: Color) -> Array:
	var row = HBoxContainer.new()
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(220, 14)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fg = StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(2)
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.04, 0.03, 0.9)
	bg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fg)
	bar.add_theme_stylebox_override("background", bg)
	row.add_child(bar)
	var text = UI.label("", 11)
	text.custom_minimum_size = Vector2(64, 0)
	row.add_child(text)
	return [bar, text, row]

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	var s = _stats()
	if s == null or _health_bar == null:
		return
	var health = float(s.get_health())
	var max_health = maxf(1.0, float(s.get_max_health()))
	var stamina = float(s.get_stamina())
	var max_stamina = maxf(1.0, float(s.get_max_stamina()))
	_health_bar.max_value = max_health
	_health_bar.value = health
	_health_text.text = "%d / %d" % [roundi(health), roundi(max_health)]
	_stamina_bar.max_value = max_stamina
	_stamina_bar.value = stamina
	_stamina_text.text = "%d / %d" % [roundi(stamina), roundi(max_stamina)]
	_level.text = "Level %d" % int(s.get_level())
	if _last_health >= 0.0 and health < _last_health - 0.01:
		hit()
	_last_health = health

## Brief red flash at the screen's edge and on the health bar
func hit() -> void:
	hit_flashes += 1
	if not is_inside_tree():
		return
	if _flash_tween:
		_flash_tween.kill()
	_flash.color.a = 0.28
	_health_bar.modulate = Color(1.6, 1.0, 1.0)
	_flash_tween = create_tween().set_parallel()
	_flash_tween.tween_property(_flash, "color:a", 0.0, FLASH_SECONDS)
	_flash_tween.tween_property(_health_bar, "modulate", Color.WHITE, FLASH_SECONDS)

## A short line under the bars ("There is nothing to work with here.")
func show_note(text: String) -> void:
	_note.text = text
	_note.visible = true
	_note.modulate.a = 1.0
	if not is_inside_tree():
		return
	if _note_tween:
		_note_tween.kill()
	_note_tween = create_tween()
	_note_tween.tween_interval(NOTE_SECONDS)
	_note_tween.tween_property(_note, "modulate:a", 0.0, 0.5)
	_note_tween.tween_callback(func(): _note.visible = false)

func get_note() -> String:
	return _note.text if _note.visible else ""

func get_health_text() -> String:
	return _health_text.text

func get_stamina_text() -> String:
	return _stamina_text.text

func get_level_text() -> String:
	return _level.text

func _stats() -> Node:
	return stats if stats else UI.autoload("PlayerStats")
