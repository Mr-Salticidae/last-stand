# Dev tool: compile-check every .gd in the project.
# Run:  godot --headless --path . --script res://tools/validate_scripts.gd
# Exits 1 if any script fails to compile. Unlike `--check-only`, this boots the
# engine fully, so autoload identifiers (Settings / AudioManager / ...) resolve.
extends SceneTree

const SCAN_ROOTS: Array[String] = ["res://scripts", "res://tools"]

func _initialize() -> void:
	var failed: Array[String] = []
	var checked: int = 0
	var stack: Array[String] = SCAN_ROOTS.duplicate()

	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var d: DirAccess = DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var entry: String = d.get_next()
		while entry != "":
			var full: String = dir_path.path_join(entry)
			if d.current_is_dir():
				stack.append(full)
			elif entry.ends_with(".gd") and full != get_script().resource_path:
				checked += 1
				# CACHE_MODE_IGNORE forces a real recompile instead of reusing
				# whatever the editor already cached.
				var res: Resource = ResourceLoader.load(full, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
				# A script that fails to compile still comes back as a non-null
				# GDScript object, so null-checking alone reports every file as
				# healthy. reload() is what actually surfaces the compile status.
				var gd: GDScript = res as GDScript
				if gd == null or gd.reload(true) != OK:
					failed.append(full)
			entry = d.get_next()
		d.list_dir_end()

	print("VALIDATE checked=%d failed=%d" % [checked, failed.size()])
	for f in failed:
		print("  FAIL ", f)
	quit(1 if failed.size() > 0 else 0)
