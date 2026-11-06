@tool
extends PopupPanel
## Slot grid plus one button per popup action, built in code.

const EditorColors = preload("uid://cpw0fsrs38esk") #! resolve UtilE.Colors

const CLOSE_DELAY = 0.8

signal slot_chosen(slot:int)

var timer:Timer
var _mouse_in_panel := true
var option_chosen := false


func _init() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	popup_hide.connect(hide_and_free)
	
	timer = Timer.new()
	add_child(timer)
	timer.wait_time = CLOSE_DELAY
	timer.one_shot = true

func open(control:Control, current_slot, available_slots:Array, actions:Array):
	var vbox = VBoxContainer.new()
	add_child(vbox)
	
	var grid = SlotGrid.new(current_slot, available_slots)
	grid.slot_clicked.connect(_on_slot_clicked)
	vbox.add_child(grid)
	
	if not actions.is_empty():
		var separator = Control.new()
		separator.custom_minimum_size.y = 8 * EditorInterface.get_editor_scale()
		vbox.add_child(separator)
	
	for action in actions:
		vbox.add_child(_new_action_button(action))
	
	var window = control.get_window()
	if window == EditorInterface.get_base_control().get_window():
		EditorInterface.get_base_control().add_child(self)
	else:
		window.add_child(self)
	
	var popup_size = Vector2i(get_contents_minimum_size())
	var popup_pos = DisplayServer.mouse_get_position() - (popup_size / 2)
	position = popup_pos
	size = popup_size
	
	if window.current_screen == 0: ##prefer manual hide and show for slow machines
		popup(Rect2i(popup_pos, popup_size))
	
	show()

func _new_action_button(action:Dictionary) -> Button:
	var button = Button.new()
	button.text = action.get("text", "")
	button.focus_mode = Control.FOCUS_NONE
	
	var icon = action.get("icon")
	if icon is String:
		icon = EditorInterface.get_editor_theme().get_icon(icon, "EditorIcons")
	if icon is Texture2D:
		button.icon = icon
	
	if action.get("active", false):
		var accent = EditorColors.get_theme_color(EditorColors.ThemeColor.ACCENT)
		button.add_theme_color_override("icon_normal_color", accent)
	
	button.pressed.connect(_on_action_pressed.bind(action.get("callable")))
	return button


func _on_slot_clicked(slot:int):
	option_chosen = true
	hide_and_free()
	slot_chosen.emit(slot)

func _on_action_pressed(callable:Callable):
	option_chosen = true
	hide_and_free()
	callable.call()

func _on_mouse_entered():
	_mouse_in_panel = true
	if not timer.is_stopped():
		timer.timeout.emit()
	timer.stop()

func _on_mouse_exited():
	if option_chosen:
		return
	_mouse_in_panel = false
	timer.start()
	await timer.timeout
	if _mouse_in_panel:
		return
	
	hide_and_free()

func hide_and_free():
	hide()
	queue_free()


## Port of the engine's DockSlotGrid, which scripts can't instantiate. Its rects aren't exposed
## either, so they are copied from each slot's grid_rect.
class SlotGrid extends Control:
	const GRID_SIZE = Vector2(8, 8)
	const MARGINS = Vector2(4, 8)
	const CELL_SIZE = Vector2(24, 12)
	
	const BOTTOM_ROW_SLOTS = [9, 10] # don't exist before 4.7, the grid drops their row without them
	const ROWS_WITHOUT_BOTTOM_ROW = 6
	
	# Indexed by DockSlot value.
	const SLOT_RECTS = [
		Rect2i(0, 0, 1, 3), Rect2i(0, 3, 1, 3), Rect2i(1, 0, 1, 3), Rect2i(1, 3, 1, 3), # left
		Rect2i(6, 0, 1, 3), Rect2i(6, 3, 1, 3), Rect2i(7, 0, 1, 3), Rect2i(7, 3, 1, 3), # right
		Rect2i(2, 4, 4, 2), Rect2i(0, 6, 4, 2), Rect2i(4, 6, 4, 2), # bottom, bottom left, bottom right
		Rect2i(2, 0, 4, 4), # main screen
	]
	
	const COLOR_HOVERED = Color(0.8, 0.8, 0.8, 0.8)
	const COLOR_AVAILABLE = Color(0.6, 0.6, 0.6, 0.4)
	const COLOR_UNAVAILABLE = Color(0.6, 0.6, 0.6, 0.1)
	
	signal slot_clicked(slot:int)
	
	var _current_slot
	var _available_slots:Array
	var _shown_slots:Array = []
	var _grid_size := GRID_SIZE
	var _hovered_slot := -1
	
	func _init(current_slot, available_slots:Array) -> void:
		_current_slot = current_slot
		_available_slots = available_slots
		mouse_exited.connect(_set_hovered_slot.bind(-1))
		for slot in SLOT_RECTS.size():
			if slot in available_slots or not slot in BOTTOM_ROW_SLOTS:
				_shown_slots.append(slot)
		if _shown_slots.size() + BOTTOM_ROW_SLOTS.size() == SLOT_RECTS.size():
			_grid_size.y = ROWS_WITHOUT_BOTTOM_ROW
	
	func get_slot_rect(slot:int) -> Rect2:
		var ed_scale = EditorInterface.get_editor_scale()
		var rect = Rect2(SLOT_RECTS[slot])
		if is_layout_rtl():
			rect.position.x = GRID_SIZE.x - rect.position.x - rect.size.x
		var pos = rect.position * CELL_SIZE * ed_scale + (rect.position + Vector2(0, 1)) * MARGINS * ed_scale
		var grid_size = rect.size * CELL_SIZE * ed_scale + (rect.size - Vector2.ONE) * MARGINS * ed_scale
		return Rect2(pos, grid_size)
	
	func get_slot_at(point:Vector2) -> int:
		for slot in _shown_slots:
			if get_slot_rect(slot).has_point(point):
				return slot
		return -1
	
	func _get_minimum_size() -> Vector2:
		var ed_scale = EditorInterface.get_editor_scale()
		return _grid_size * CELL_SIZE * ed_scale + (_grid_size - Vector2(1, 0)) * MARGINS * ed_scale
	
	func _draw() -> void:
		var current_color = get_theme_color(&"mono_color", &"Editor")
		for slot in _shown_slots:
			var color = COLOR_AVAILABLE
			if slot == _current_slot:
				color = current_color
			elif not slot in _available_slots:
				color = COLOR_UNAVAILABLE
			elif slot == _hovered_slot:
				color = COLOR_HOVERED
			draw_rect(get_slot_rect(slot), color)
	
	func _gui_input(event: InputEvent) -> void:
		if event is not InputEventMouse:
			return
		var slot = get_slot_at(event.position)
		_set_hovered_slot(slot)
		if slot == -1 or slot == _current_slot or not slot in _available_slots:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			slot_clicked.emit(slot)
	
	func _set_hovered_slot(slot:int):
		if slot != _hovered_slot:
			_hovered_slot = slot
			queue_redraw()
