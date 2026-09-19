extends Window

const UVersion = preload("uid://dn156lc18d1vt") #! resolve UtilR.UVersion
const UWindow = preload("uid://d1yl3cuumcudy") #! resolve UtilR.Nodes.UWindow
const EditorColors = preload("uid://cpw0fsrs38esk") #! resolve UtilE.Colors

func _init(control, empty_panel:=false, window_size:=Vector2i(1200, 800), window_pos=null) -> void:
	
	
	
	if window_pos == null:
		initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_SCREEN_WITH_MOUSE_FOCUS
	else:
		initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
		position = window_pos
	
	size = window_size
	
	EditorInterface.get_base_control().add_child(self)
	var panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(panel)
	always_on_top = true
	
	var panel_sb
	var minor = UVersion.get_minor_version()
	if minor < 6:
		panel_sb = panel.get_theme_stylebox("panel").duplicate() # as StyleBoxFlat
	else: #elif version <= 7: # Deal with when there is an issue in new version
		panel_sb = EditorInterface.get_editor_theme().get_stylebox("panel", "Panel").duplicate()
		panel_sb.content_margin_top += 2 * EditorInterface.get_editor_scale()
		panel_sb.content_margin_bottom += 2 * EditorInterface.get_editor_scale()
	
	panel_sb.draw_center = true
	panel_sb.bg_color = EditorColors.get_theme_color(EditorColors.ThemeColor.BASE)
	panel_sb.set_corner_radius_all(0)
	panel.add_theme_stylebox_override("panel", panel_sb)
	
	if empty_panel:
		panel_sb = StyleBoxEmpty.new()
		panel.add_theme_stylebox_override("panel", panel_sb)
	
	if is_instance_valid(control.get_parent()):
		control.reparent(panel)
	else:
		panel.add_child(control)
	
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	control.show()
	
	
	if window_pos == null:
		position = UWindow.get_window_global_position(self, false)
