@tool
extends RefCounted
## Runs the dock suites on every other supported Godot. The toolchain needs 4.6+, so CI
## resolves deps once and this copies the resolved addons (minus the toolchain) into a fresh
## project per version, then runs that version's editor on it in parallel. It only runs inside a
## gdpackage test workspace; elsewhere, addons/ holds far more than this package needs.

# A pre-release is an early warning for the next minor; swap it for the stable once released.
const VERSIONS = ["4.4.1-stable", "4.5.1-stable", "4.6.3-stable", "4.7.2-stable", "4.8-beta2"]
const SUITES = [
	"res://addons/_lib/dock_manager/_export_ignore/test/dock_manager_test.gd",
	"res://addons/_lib/dock_manager/_export_ignore/test/dock_scenarios_test.gd",
]
const TEST_RUNNER = "res://addons/_lib/util_r/src/test/test_runner.gd"
const WORKSPACE_MARKER = "res://addons/pe_release_autorun"
const SKIP_DIRS = ["gdpackage", "package_exporter", "pe_release_autorun", ".git", ".godot"]
const PROJECTS_DIR = "user://dock_manager_versions"
const AUTORUN_DIR = "dm_autorun"
const RESULT_PREFIX = "DM_RESULT "

const CHILD_TIMEOUT_SEC = 240 # import + editor boot + suite; the toolchain's whole job gets 600

const _AUTORUN = """@tool
extends EditorPlugin
# Written by godot_versions_test.gd: runs one suite once the scan ends, prints the report, quits.

var _deadline := 0

func _enter_tree() -> void:
	_run.call_deferred()

# A script error ends _run without quitting; the deadline stops the parent waiting on it.
func _process(_delta:float) -> void:
	if _deadline > 0 and Time.get_ticks_msec() > _deadline:
		_finish({"ok": false, "output": ["timed out, or the suite stopped on a script error"]}, 3)

func _run() -> void:
	var fs = EditorInterface.get_resource_filesystem()
	await get_tree().process_frame
	while fs.is_scanning():
		await get_tree().process_frame
	_deadline = Time.get_ticks_msec() + %d * 1000
	var report = await load("%s").run_files(%s)
	var ok = report.failed == 0 and report.invalid.is_empty() and not report.suites.is_empty()
	_finish({"ok": ok, "report": report}, 0 if ok else 1)

func _finish(result:Dictionary, code:int) -> void:
	_deadline = 0
	print("%s" + JSON.stringify(result))
	get_tree().quit(code)
"""


static func run_tests() -> Dictionary:
	if not DirAccess.dir_exists_absolute(WORKSPACE_MARKER):
		return {"result": 0, "output": ["skipped: not in a gdpackage test workspace"]}
	var out: Array = []
	var running = Engine.get_version_info()
	var runs = []
	for version in VERSIONS:
		var mm = _major_minor(version)
		if mm == [running.major, running.minor]:
			continue # the suites already run in this process
		var run = {"version": version, "error": ""}
		runs.append(run)
		var bin = _godot_for(version)
		if bin.has("error"):
			run.error = bin.error
			continue
		var project = _make_project(version, mm)
		if project == "":
			run.error = "could not build a project for " + version
			continue
		run.log = project.path_join("run.log")
		var cmd = "%s --headless --path %s --import > %s 2>&1; exec %s --headless --editor --path %s >> %s 2>&1" % [
			_q(bin.path), _q(project), _q(run.log), _q(bin.path), _q(project), _q(run.log)]
		run.pid = OS.create_process("/bin/sh", ["-c", cmd])
		if run.pid <= 0:
			run.error = "could not start " + bin.path

	# Await frames rather than block, so the children run in parallel and the editor keeps ticking.
	var tree = Engine.get_main_loop() as SceneTree
	var start = Time.get_ticks_msec()
	while runs.any(func(r): return r.get("pid", 0) > 0 and OS.is_process_running(r.pid)):
		if Time.get_ticks_msec() - start > CHILD_TIMEOUT_SEC * 1000:
			for r in runs:
				if r.get("pid", 0) > 0 and OS.is_process_running(r.pid):
					OS.kill(r.pid)
					r.error = "killed after %ds" % CHILD_TIMEOUT_SEC
			break
		await tree.process_frame

	var failures = 0
	for run in runs:
		var res = _result_of(run)
		out.append(("PASS " if res.ok else "FAIL ") + run.version + ("" if res.ok else ": " + res.why))
		if not res.ok:
			failures += 1
		for line in res.lines:
			out.append("    " + line)
	out.push_front("dock_manager across %d other version(s) in %ds" % [runs.size(), (Time.get_ticks_msec() - start) / 1000])
	return {"result": failures, "output": out}


static func _major_minor(version:String) -> Array:
	var parts = version.get_slice("-", 0).split(".")
	return [int(parts[0]), int(parts[1])]


## {path} of a Godot editor for `version`: ENR_GODOT_<major>_<minor> if set, else on Linux a
## godot-builds download kept under the gdpackage cache, which CI already caches.
static func _godot_for(version:String) -> Dictionary:
	var mm = _major_minor(version)
	var env = "ENR_GODOT_%d_%d" % mm
	if OS.has_environment(env):
		return {"path": OS.get_environment(env)}
	if OS.get_name() != "Linux":
		return {"error": "set %s to a Godot %s editor binary" % [env, version]}
	var dir = OS.get_cache_dir().path_join("gdpackage").path_join("godot").path_join(version)
	var bin = dir.path_join("godot")
	if FileAccess.file_exists(bin):
		return {"path": bin}
	DirAccess.make_dir_recursive_absolute(dir)
	var name = "Godot_v%s_linux.x86_64" % version
	var url = "https://github.com/godotengine/godot-builds/releases/download/%s/%s.zip" % [version, name]
	var zip = dir.path_join("godot.zip")
	var output = []
	if OS.execute("curl", ["-fsSL", "-o", zip, url], output, true) != 0:
		return {"error": "download failed: %s %s" % [url, "".join(output).strip_edges()]}
	if OS.execute("unzip", ["-q", "-o", zip, "-d", dir], output, true) != 0:
		return {"error": "unzip failed: " + "".join(output).strip_edges()}
	DirAccess.remove_absolute(zip)
	if DirAccess.rename_absolute(dir.path_join(name), bin) != OK:
		return {"error": "no %s in %s" % [name, url]}
	OS.execute("chmod", ["+x", bin])
	return {"path": bin}


## A fresh project per version: each editor writes its own .godot/, and an older one must never
## read a newer one's cache.
static func _make_project(version:String, mm:Array) -> String:
	var project = ProjectSettings.globalize_path(PROJECTS_DIR).path_join(version)
	_remove_dir(project)
	if not _copy_dir(ProjectSettings.globalize_path("res://addons"), project.path_join("addons")):
		return ""
	var autorun = project.path_join("addons").path_join(AUTORUN_DIR)
	DirAccess.make_dir_recursive_absolute(autorun)
	var cfg = '[plugin]\n\nname="%s"\ndescription=""\nauthor=""\nversion="1.0"\nscript="plugin.gd"\n' % AUTORUN_DIR
	var godot = 'config_version=5\n\n[application]\n\nconfig/name="DM %s"\nconfig/features=PackedStringArray("%d.%d")\n\n[editor_plugins]\n\nenabled=PackedStringArray("res://addons/%s/plugin.cfg")\n' % [
		version, mm[0], mm[1], AUTORUN_DIR]
	var ok = _write(autorun.path_join("plugin.cfg"), cfg)
	ok = ok and _write(autorun.path_join("plugin.gd"), _AUTORUN % [CHILD_TIMEOUT_SEC, TEST_RUNNER, JSON.stringify(SUITES), RESULT_PREFIX])
	ok = ok and _write(project.path_join("project.godot"), godot)
	return project if ok else ""


## {ok, why, lines}: the child's report, plus any SCRIPT ERROR it logged, the same rule as test CI.
static func _result_of(run:Dictionary) -> Dictionary:
	if run.error != "":
		return {"ok": false, "why": run.error, "lines": []}
	# 4.4 colours its log lines, which would hide them from the SCRIPT ERROR check.
	var ansi = RegEx.create_from_string("\u001b\\[[0-9;]*m")
	var text = ansi.sub(FileAccess.get_file_as_string(run.log), "", true)
	var result = null
	var errors = []
	for line in text.split("\n"):
		if line.begins_with(RESULT_PREFIX):
			result = JSON.parse_string(line.trim_prefix(RESULT_PREFIX))
		elif line.begins_with("SCRIPT ERROR:"):
			errors.append(line)
	if not result is Dictionary:
		var tail = Array(text.strip_edges().split("\n")).slice(-15)
		return {"ok": false, "why": "no result line (crashed?), log: " + run.log, "lines": tail}
	var lines = []
	for suite in result.get("report", {}).get("suites", []):
		lines.append_array(suite.output)
	lines.append_array(result.get("output", []))
	lines.append_array(errors)
	if not result.ok:
		return {"ok": false, "why": "suite failed", "lines": lines}
	if not errors.is_empty():
		return {"ok": false, "why": "%d SCRIPT ERROR(s)" % errors.size(), "lines": errors}
	return {"ok": true, "why": "", "lines": []}


static func _copy_dir(from:String, to:String) -> bool:
	DirAccess.make_dir_recursive_absolute(to)
	var dir = DirAccess.open(from)
	if dir == null:
		return false
	dir.include_hidden = true
	for f in dir.get_files():
		if DirAccess.copy_absolute(from.path_join(f), to.path_join(f)) != OK:
			return false
	for d in dir.get_directories():
		if d in SKIP_DIRS:
			continue
		if not _copy_dir(from.path_join(d), to.path_join(d)):
			return false
	return true


static func _remove_dir(path:String) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		_remove_dir(path.path_join(d))
	DirAccess.remove_absolute(path)


static func _write(path:String, text:String) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	return true


static func _q(s:String) -> String:
	return "'" + s.replace("'", "'\\''") + "'"
