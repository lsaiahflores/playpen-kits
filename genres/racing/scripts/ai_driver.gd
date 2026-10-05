class_name AIDriver
extends Node
## Drives a Kart around the track: steers toward a point ahead on the centre line,
## lifts for sharp corners, drifts the big ones, and rubber-bands gently so the race
## stays close (leaders ease off, stragglers get a small edge). Tweak `skill`.

var kart: Kart
var track: RaceTrack
var player: Kart
@export var skill := 0.9            # 0.8 easy .. 1.0 hard
@export var lookahead := 14.0
@export var lane := 0.0             # -1..1 across the road, so racers don't stack
var _drift_timer := 0.0

func setup(k: Kart, t: RaceTrack, p: Kart, s := 0.9, lane_offset := 0.0) -> void:
	kart = k
	track = t
	player = p
	skill = s
	lane = lane_offset
	kart.is_ai = true

func _physics_process(delta: float) -> void:
	if kart == null or kart.sphere == null or track == null:
		return
	var off := track.offset_of(kart.global_position)
	var look := lookahead + absf(kart.speed) * 0.25
	var target := track.point_ahead(off, look)
	var after := track.point_ahead(off, look * 2.0)
	# offset the target toward this driver's lane
	var tan := (after - target).normalized()
	var right := tan.cross(Vector3.UP).normalized()
	target += right * lane * track.road_width * 0.55
	var to := target - kart.global_position
	to.y = 0.0
	var fwd := Vector3(sin(kart.yaw), 0, cos(kart.yaw))
	var ang := fwd.signed_angle_to(to.normalized(), Vector3.UP)
	kart.steer_in = clampf(-ang * 1.7, -1.0, 1.0)
	# corner sharpness ahead (angle between now and further ahead)
	var d1 := (target - kart.global_position)
	var d2 := (after - target)
	var bend := absf(Vector3(d1.x, 0, d1.z).signed_angle_to(Vector3(d2.x, 0, d2.z), Vector3.UP))
	var target_speed := kart.max_speed * skill * (1.0 - clampf(bend * 0.9, 0.0, 0.55))
	# rubber band against the player
	if player and player.sphere:
		var gap := track.offset_of(kart.global_position) - track.offset_of(player.global_position)
		if gap > track.length * 0.5:
			gap -= track.length
		elif gap < -track.length * 0.5:
			gap += track.length
		target_speed *= clampf(1.0 - gap / 260.0, 0.88, 1.08)
	kart.throttle_in = 1.0 if kart.speed < target_speed else 0.0
	kart.brake_in = 0.6 if kart.speed > target_speed + 6.0 else 0.0
	# drift the long, sharp corners
	_drift_timer -= delta
	kart.drift_in = bend > 0.55 and kart.speed > 20.0 and absf(kart.steer_in) > 0.5
	kart.off_road = track.distance_to_center(kart.global_position) > track.road_width + 1.2
