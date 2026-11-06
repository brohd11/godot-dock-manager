extends RefCounted
## Slot values, saved layout migration and the popup grid. Placement needs a running editor, so
## it isn't covered here.

const DockPopup = preload("res://addons/_lib/dock_manager/src/dock_popup/dock_popup.gd")
const EngineBackend = preload("res://addons/_lib/dock_manager/src/backend/engine_backend.gd")

static var _failures:int
static var _out:Array


static func run_tests() -> Dictionary:
	_failures = 0
	_out = []
	_test_slot_conversion()
	_test_saved_slot()
	_test_grid()
	_test_engine_slots()
	return {"result": _failures, "output": _out}


static func _check(label:String, condition:bool) -> void:
	if not condition:
		_failures += 1
	_out.append("%s: %s" % ["PASS" if condition else "FAIL", label])

static func _test_slot_conversion() -> void:
	_check("floating code", DockManager.legacy_to_slot(-3) == DockManager.DOCK_SLOT_NONE)
	_check("bottom code", DockManager.legacy_to_slot(-2) == DockManager.DOCK_SLOT_BOTTOM)
	_check("main screen code", DockManager.legacy_to_slot(-1) == DockManager.DOCK_SLOT_MAIN_SCREEN)
	for code in [-3, -2, -1, 0, 3, 7, 9, 10]:
		_check("code %d round trips" % code, DockManager.slot_to_legacy(DockManager.legacy_to_slot(code)) == code)
	_check("side slots match the engine", EditorPlugin.DOCK_SLOT_RIGHT_BR == 7)

## CURRENT_DOCK held the old Slot enum: floating 0, bottom 1, main screen 2, then side slots from 3.
static func _test_saved_slot() -> void:
	var Keys = DockManager.Keys
	_check("nothing saved", DockManager._read_saved_slot({}) == null)
	_check("old floating", DockManager._read_saved_slot({Keys.CURRENT_DOCK: 0.0}) == DockManager.DOCK_SLOT_NONE)
	_check("old bottom", DockManager._read_saved_slot({Keys.CURRENT_DOCK: 1.0}) == DockManager.DOCK_SLOT_BOTTOM)
	_check("old main screen", DockManager._read_saved_slot({Keys.CURRENT_DOCK: 2.0}) == DockManager.DOCK_SLOT_MAIN_SCREEN)
	_check("old side slot", DockManager._read_saved_slot({Keys.CURRENT_DOCK: 3.0}) == 0)
	_check("new key wins", DockManager._read_saved_slot({Keys.SLOT: 9.0, Keys.CURRENT_DOCK: 1.0}) == 9)

static func _test_grid() -> void:
	var rects = DockPopup.SlotGrid.SLOT_RECTS
	var grid = DockPopup.SlotGrid.new(0, range(rects.size()))
	_check("every slot has a rect", rects.size() == DockManager.DOCK_SLOT_MAIN_SCREEN + 1)
	
	var cells = {}
	for slot in rects.size():
		for x in range(rects[slot].position.x, rects[slot].end.x):
			for y in range(rects[slot].position.y, rects[slot].end.y):
				cells[Vector2i(x, y)] = cells.get(Vector2i(x, y), 0) + 1
	_check("rects tile the grid exactly", cells.size() == 64 and cells.values().max() == 1)
	
	var bounds = Rect2(Vector2.ZERO, grid._get_minimum_size())
	for slot in rects.size():
		var rect = grid.get_slot_rect(slot)
		_check("slot %d fits the grid" % slot, bounds.encloses(rect))
		_check("slot %d found at its center" % slot, grid.get_slot_at(rect.get_center()) == slot)
	_check("margin hits no slot", grid.get_slot_at(Vector2(-1, -1)) == -1)
	
	var no_bottom_row = DockPopup.SlotGrid.new(0, range(DockManager.DOCK_SLOT_BOTTOM + 1))
	_check("grid drops the bottom row", no_bottom_row._get_minimum_size().y < grid._get_minimum_size().y)
	_check("width unchanged", no_bottom_row._get_minimum_size().x == grid._get_minimum_size().x)
	for slot in DockPopup.SlotGrid.BOTTOM_ROW_SLOTS:
		_check("slot %d not clickable" % slot, no_bottom_row.get_slot_at(grid.get_slot_rect(slot).get_center()) == -1)
	var short_bounds = Rect2(Vector2.ZERO, no_bottom_row._get_minimum_size())
	_check("bottom panel fits the short grid", short_bounds.encloses(no_bottom_row.get_slot_rect(DockManager.DOCK_SLOT_BOTTOM)))
	no_bottom_row.free()
	grid.free()

static func _test_engine_slots() -> void:
	var slots = EngineBackend.new(null).get_available_slots()
	_check("engine offers every slot", slots.size() == 12 and DockManager.DOCK_SLOT_MAIN_SCREEN in slots)
