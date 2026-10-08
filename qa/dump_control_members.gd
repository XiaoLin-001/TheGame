extends SceneTree
func _init() -> void:
	var names := {}
	for cls in ["Control", "Node2D", "RefCounted"]:
		var d := {}
		for m in ClassDB.class_get_method_list(cls):
			d[m["name"]] = 1
		for p in ClassDB.class_get_property_list(cls):
			d[p["name"]] = 1
		for sg in ClassDB.class_get_signal_list(cls):
			d[sg["name"]] = 1
		for c in ClassDB.class_get_integer_constant_list(cls):
			d[c] = 1
		for e in ClassDB.class_get_enum_list(cls):
			d[e] = 1
		names[cls] = d.keys()
	var f := FileAccess.open(OS.get_environment("OUT"), FileAccess.WRITE)
	f.store_string(JSON.stringify(names))
	f.close()
	quit()
