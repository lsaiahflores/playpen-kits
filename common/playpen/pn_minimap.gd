class_name PNMinimap
extends Control
## Playpen kit: a GTA-style round minimap that rotates with the camera.
## Cheap: it DRAWS (no second viewport) — streets/blocks/water from a plain data
## dictionary, plus live dots for anything in the groups you list (collectibles,
## enemies, checkpoints). Player arrow stays in the centre pointing up.
##
##   var mm := PNMinimap.new()
##   mm.setup(player, camera_pivot, {"blocks": [Rect2...], "streets": [Rect2...], "water": [Rect2...]},
##            {"collectible": Color(1, .85, .2), "enemy": Color.RED})
##   hud.add_child(mm)

var target: Node3D
var cam: Node3D
var map := {}
var group_colors := {}
var view_radius := 55.0       # metres from centre to the edge of the disc
var diameter := 190.0

func setup(player: Node3D, camera_node: Node3D, map_data: Dictionary, groups := {}, size_px := 190.0) -> void:
	target = player
	cam = camera_node
	map = map_data
	group_colors = groups
	diameter = size_px
	custom_minimum_size = Vector2(diameter, diameter)
	size = Vector2(diameter, diameter)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Circular mask: a Panel with a fully-rounded StyleBox clips its CHILDREN, so
	# the map is drawn by a child canvas (a node's own _draw isn't clipped by itself).
	var disc := Panel.new()
	disc.name = "Disc"
	disc.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	disc.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PNLook.color("ui_bg", Color(0.08, 0.15, 0.25)), 0.85)
	sb.set_corner_radius_all(int(diameter * 0.5))
	sb.border_color = Color(str(PNLook.look.get("ui", {}).get("accent", "#ffcf40")))
	sb.set_border_width_all(4)
	disc.add_theme_stylebox_override("panel", sb)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(disc)
	var canvas := _Canvas.new()
	canvas.owner_map = self
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(canvas)
	_canvas = canvas

var _canvas: Control

class _Canvas extends Control:
	var owner_map: PNMinimap
	func _draw() -> void:
		if owner_map:
			owner_map._paint(self)

var _accum := 0.0
func _process(delta: float) -> void:
	# A minimap does not need 60 redraws a second — 12 Hz is smooth enough and
	# saves a lot of canvas work on a weak GPU.
	_accum += delta
	if _accum >= 1.0 / 12.0 and _canvas:
		_accum = 0.0
		_canvas.queue_redraw()

func _w2m(p: Vector3, origin: Vector3) -> Vector2:
	var k := diameter * 0.5 / view_radius
	return Vector2(p.x - origin.x, p.z - origin.z) * k

func _paint(c: Control) -> void:
	if target == null or not is_instance_valid(target):
		return
	var ctr := Vector2(diameter, diameter) * 0.5
	var yaw := cam.global_rotation.y if cam and is_instance_valid(cam) else target.global_rotation.y
	var origin := target.global_position
	c.draw_set_transform(ctr, yaw, Vector2.ONE)   # rotate the world so the camera looks "up"
	var k := diameter * 0.5 / view_radius
	for r in map.get("water", []):
		c.draw_rect(Rect2(_w2m(Vector3(r.position.x, 0, r.position.y), origin), r.size * k), Color(PNLook.color("water", Color(0.2, 0.7, 0.9)), 0.9))
	for r in map.get("blocks", []):
		c.draw_rect(Rect2(_w2m(Vector3(r.position.x, 0, r.position.y), origin), r.size * k), PNLook.color("building", Color(0.7, 0.65, 0.6)).darkened(0.1))
	for r in map.get("streets", []):
		c.draw_rect(Rect2(_w2m(Vector3(r.position.x, 0, r.position.y), origin), r.size * k), Color(0.92, 0.9, 0.82, 0.55))
	# polylines (a race track, a river): {"points": PackedVector2Array of world x,z, "width": px, "color": Color}
	for ln in map.get("lines", []):
		var pts := PackedVector2Array()
		for wp in ln["points"]:
			pts.append(_w2m(Vector3(wp.x, 0, wp.y), origin))
		if pts.size() > 1:
			c.draw_polyline(pts, ln.get("color", Color(1, 1, 1, 0.8)), float(ln.get("width", 5.0)))
	for g in group_colors:
		for n in get_tree().get_nodes_in_group(g):
			if not (n is Node3D):
				continue
			var m := _w2m((n as Node3D).global_position, origin)
			if m.length() > diameter * 0.5:
				continue   # off the disc: not drawn at all (fewer draw calls)
			var col: Color = group_colors[g]
			c.draw_rect(Rect2(m - Vector2(4.5, 4.5), Vector2(9, 9)), Color(0, 0, 0, 0.55))
			c.draw_rect(Rect2(m - Vector2(3, 3), Vector2(6, 6)), col)
	c.draw_set_transform(ctr, 0.0, Vector2.ONE)
	# player arrow (relative to the camera direction)
	var rel := target.global_rotation.y - yaw
	var arrow := PackedVector2Array([Vector2(0, -9), Vector2(6, 7), Vector2(0, 3), Vector2(-6, 7)])
	var rot := PackedVector2Array()
	for p in arrow:
		rot.append(p.rotated(-rel + PI) * 1.0)
	c.draw_colored_polygon(rot, Color(1, 1, 1))
	c.draw_polyline(PackedVector2Array([rot[0], rot[1], rot[2], rot[3], rot[0]]), Color(0, 0, 0, 0.8), 1.5)
