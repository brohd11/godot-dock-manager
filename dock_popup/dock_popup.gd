@tool
extends PopupPanel

const EditorColors = preload("uid://cpw0fsrs38esk") #! resolve UtilE.Colors

const CANCEL_STRING = "CANCEL_STRING"

@onready var panels_h_box: HBoxContainer = %PanelsHBox
@onready var left_ul: Button = %LeftUL
@onready var left_bl: Button = %LeftBL
@onready var left_ur: Button = %LeftUR
@onready var left_br: Button = %LeftBR
@onready var main_screen: Button = %MainScreen
@onready var bottom_panel: Button = %BottomPanel
@onready var right_ul: Button = %RightUL
@onready var right_bl: Button = %RightBL
@onready var right_ur: Button = %RightUR
@onready var right_br: Button = %RightBR
@onready var make_floating_button: Button = %MakeFloatingButton
@onready var free_instance_button: Button = %FreeInstanceButton
@onready var reload_scene_button: Button = %ReloadSceneButton
@onready var always_on_top_button: Button = %AlwaysOnTopButton

var timer:Timer
var _mouse_in_panel := true

var option_chosen := false

signal handled(arg)

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	popup_hide.connect(_on_popup_hide)
	
	timer = Timer.new()
	add_child(timer)
	timer.wait_time = 0.8
	timer.one_shot = true
	
	left_ul.pressed.connect(_button_pressed.bind(0))
	left_bl.pressed.connect(_button_pressed.bind(1))
	left_ur.pressed.connect(_button_pressed.bind(2))
	left_br.pressed.connect(_button_pressed.bind(3))
	main_screen.pressed.connect(_button_pressed.bind(-1))
	bottom_panel.pressed.connect(_button_pressed.bind(-2))
	right_ul.pressed.connect(_button_pressed.bind(4))
	right_bl.pressed.connect(_button_pressed.bind(5))
	right_ur.pressed.connect(_button_pressed.bind(6))
	right_br.pressed.connect(_button_pressed.bind(7))
	
	make_floating_button.pressed.connect(_button_pressed.bind(-3))
	free_instance_button.pressed.connect(_button_pressed.bind(20))
	reload_scene_button.pressed.connect(_button_pressed.bind(30))
	always_on_top_button.pressed.connect(_button_pressed.bind(40))
	
	if not is_part_of_edited_scene():
		make_floating_button.icon = EditorInterface.get_editor_theme().get_icon("MakeFloating", &"EditorIcons")
		free_instance_button.icon = EditorInterface.get_editor_theme().get_icon("Clear", &"EditorIcons")
		reload_scene_button.icon = EditorInterface.get_editor_theme().get_icon("Reload", &"EditorIcons")
		always_on_top_button.icon = EditorInterface.get_editor_theme().get_icon("Pin", &"EditorIcons")
		
		var editor_scale = EditorInterface.get_editor_scale()
		size = size * editor_scale


func disable_main_screen():
	main_screen.disabled = true

func hide_make_floating():
	size.y = size.y - make_floating_button.size.y
	make_floating_button.hide()

func can_be_freed():
	size.y = size.y + free_instance_button.size.y
	free_instance_button.show()

func allow_reload():
	size.y = size.y + reload_scene_button.size.y
	reload_scene_button.show()

func show_always_on_top(current_setting:=false):
	size.y = size.y + always_on_top_button.size.y
	if current_setting:
		var accent = EditorColors.get_theme_color(EditorColors.ThemeColor.ACCENT)
		always_on_top_button.add_theme_color_override("icon_normal_color", accent)
	always_on_top_button.show()

func add_custom_button(callable:Callable, text:="", icon=null):
	var new_button = Button.new()
	new_button.text = text
	if icon is String:
		icon = EditorInterface.get_editor_theme().get_icon(icon, "EditorIcons")
	if icon is Texture2D:
		new_button.icon = icon
	
	always_on_top_button.get_parent().add_child(new_button)
	new_button.pressed.connect(_button_pressed.bind(callable))
	size.y = size.y + new_button.size.y


func _button_pressed(chosen):
	option_chosen = true
	handled.emit(chosen)
	hide_and_free()

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
	
	handled.emit(CANCEL_STRING)
	hide_and_free()

func _on_popup_hide():
	hide_and_free()

func hide_and_free():
	hide()
	queue_free()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		pass
