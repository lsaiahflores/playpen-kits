class_name PNAssets
extends RefCounted
## Playpen kit: resolves DESIGN-BIBLE MANIFEST NAMES to real scenes.
##
## The design bible decides every asset once and lists the names the code will use
## (design-manifest.json). Game code asks for a name: PNAssets.instance("heavy_alien_brawler", "enemy").
## Lookup order: the asset the art job produced for that name -> the catalog default for that ROLE.
## It never falls back to a gray primitive: a missing asset becomes a real default model.

const MANIFEST_PATHS := ["res://design-manifest.json", "res://brain/design-manifest.json", "res://playpen/design-manifest.json"]
const SEARCH_DIRS := ["res://assets/", "res://models/", "res://assets/models/", "res://assets/core/models/"]
const EXTS := [".glb", ".gltf", ".tscn"]
## Role defaults: real brick-toy figures that ship with the kit (copied to assets/defaults/ at build start).
const ROLE_DEFAULTS := {
	"hero": ["brick_soldier_blue"],
	"character": ["brick_soldier_blue", "brick_trooper"],
	"enemy": ["brick_soldier_red", "brick_brawler", "brick_skirmisher", "brick_warrior"],
	"npc": ["brick_trooper", "brick_warrior"],
	"vehicle": ["brick_trooper"],
	"prop": ["brick_trooper"],
}

static var _manifest := {}
static var _loaded := false
static var _missing := []

static func _load_manifest() -> void:
	if _loaded:
		return
	_loaded = true
	for p in MANIFEST_PATHS:
		if FileAccess.file_exists(p):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
			if parsed is Dictionary:
				for a in parsed.get("assets", []):
					if a is Dictionary and a.has("name"):
						_manifest[str(a["name"])] = a
				return

static func has(asset_name: String) -> bool:
	_load_manifest()
	return _manifest.has(asset_name)

## The manifest entry (type, ref) for a name, or {}.
static func entry(asset_name: String) -> Dictionary:
	_load_manifest()
	return _manifest.get(asset_name, {})

static func _find(base_name: String) -> String:
	for d in SEARCH_DIRS:
		for e in EXTS:
			var p: String = d + base_name + e
			if ResourceLoader.exists(p):
				return p
	return ""

## A PackedScene for a manifest name, or for the role default when the named asset is not there.
static func scene(asset_name: String, role: String = "character") -> PackedScene:
	var path := _find(asset_name)
	if path == "":
		if not _missing.has(asset_name):
			_missing.append(asset_name)
			push_warning("[PNAssets] '%s' not found, using the %s default" % [asset_name, role])
		var defaults: Array = ROLE_DEFAULTS.get(role, ROLE_DEFAULTS["character"])
		var pick: String = defaults[abs(asset_name.hash()) % defaults.size()]
		path = "res://assets/defaults/%s.glb" % pick
		if not ResourceLoader.exists(path):
			path = _find(pick)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene

## An instance ready to add to the tree. Returns an empty Node3D (and a warning) only if even the role default is missing.
static func instance(asset_name: String, role: String = "character") -> Node3D:
	var ps := scene(asset_name, role)
	if ps == null:
		push_warning("[PNAssets] no model available for '%s' (role %s)" % [asset_name, role])
		return Node3D.new()
	var n = ps.instantiate()
	if n is Node3D:
		return n
	var holder := Node3D.new()
	holder.add_child(n)
	return holder

## Names the code asked for that were not produced by the art job (for the BUILT report).
static func missing() -> Array:
	return _missing.duplicate()
