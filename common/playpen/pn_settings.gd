extends Node
## Playpen kit: quality, volume and fullscreen settings (autoload "PNSettings").
## Quality is auto-picked from the machine the first time (8GB RAM / integrated
## graphics -> Low or Medium) and then remembered. Everything in the ambient
## layer scales by `scale()`.

signal quality_changed(level: int)
signal settings_changed

enum Quality { LOW, MEDIUM, HIGH }
const PATH := "user://playpen_settings.cfg"
const BUS_NAMES := ["Master", "Music", "SFX", "Ambience", "UI"]

var quality: int = Quality.MEDIUM
var fullscreen := false
var volumes := {"Master": 0.9, "Music": 0.8, "SFX": 1.0, "Ambience": 0.8, "UI": 1.0}
var _loaded_from_disk := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	quality = auto_quality()
	_load()
	apply()

## Pick a sensible default for THIS machine.
static func auto_quality() -> int:
	# The Test pane runs the game as a single-threaded WEB export (WASM + WebGL2), which is far
	# slower than a native run: default to Low there, whatever the machine.
	if OS.has_feature("web"):
		return Quality.LOW
	var mem := OS.get_memory_info()
	var ram_gb := float(mem.get("physical", 0)) / 1073741824.0
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	var integrated := adapter.contains("intel") or adapter.contains("uhd") or adapter.contains("iris") \
		or adapter.contains("vega") or adapter.contains("radeon(tm) graphics") or adapter.contains("radeon graphics") \
		or adapter.contains("basic render") or adapter.contains("llvmpipe")
	var low_ram := ram_gb > 0.0 and ram_gb <= 8.5
	if low_ram and integrated:
		return Quality.LOW
	if low_ram or integrated:
		return Quality.MEDIUM if OS.get_processor_count() >= 6 else Quality.LOW
	if ram_gb >= 15.0 and OS.get_processor_count() >= 8:
		return Quality.HIGH
	return Quality.MEDIUM

## Fraction of the window the 3D world is rendered at (UI is always full res).
## Measured on an 8GB / Intel HD 620 laptop: fill-rate is the bottleneck.
func render_scale() -> float:
	match quality:
		Quality.LOW: return 0.5 if OS.has_feature("web") else 0.6
		Quality.MEDIUM: return 0.8
	return 1.0

## Multiplier for particle / critter / scatter counts at the current quality.
func scale() -> float:
	match quality:
		Quality.LOW: return 0.25 if OS.has_feature("web") else 0.35
		Quality.MEDIUM: return 0.7
	return 1.0

func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	quality_changed.emit(quality)
	settings_changed.emit()
	apply()
	save()

func set_volume(bus_name: String, linear: float) -> void:
	volumes[bus_name] = clampf(linear, 0.0, 1.0)
	_apply_volume(bus_name)
	save()

func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply()
	save()

func apply() -> void:
	for b in BUS_NAMES:
		_apply_volume(b)
	if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):   # the browser owns the window
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = Viewport.MSAA_2X if quality == Quality.HIGH else Viewport.MSAA_DISABLED

func _apply_volume(bus_name: String) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		var v: float = volumes.get(bus_name, 1.0)
		AudioServer.set_bus_volume_db(idx, -80.0 if v <= 0.001 else linear_to_db(v))

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "fullscreen", fullscreen)
	for b in volumes:
		cfg.set_value("audio", b, volumes[b])
	cfg.save(PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	_loaded_from_disk = true
	quality = int(cfg.get_value("video", "quality", quality))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	for b in volumes:
		volumes[b] = float(cfg.get_value("audio", b, volumes[b]))
