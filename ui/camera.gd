extends Camera3D
##
## Orbit / zoom / pan, on mouse and on touch.
##
## Defaults to the handoff's 45-degree elevation looking at the herd, which for
## the crossing means the middle of the field rather than the geometric centre:
## the deer starts on the right and the pack is in the middle, so the interesting
## half is the right two-thirds.
##
##   mouse   left-drag orbits, right- or middle-drag pans, wheel zooms
##   touch   one finger orbits, two fingers pinch to zoom and drag to pan
##
## Pitch is clamped just short of straight down and just above the horizon: a
## camera that goes under the ground plane is a camera nobody can recover.
##

const MIN_PITCH := deg_to_rad(8.0)
const MAX_PITCH := deg_to_rad(84.0)
const MIN_DIST := 12.0
const MAX_DIST := 340.0

var target := Vector3.ZERO
var distance := 150.0
var yaw := deg_to_rad(-90.0)
var pitch := deg_to_rad(45.0)

var _orbiting := false
var _panning := false
var _touches := {}
var _pinch_dist := 0.0
var _home := {}


func setup(centre: Vector3, dist: float) -> void:
	target = centre
	distance = dist
	_home = {"t": centre, "d": dist, "y": yaw, "p": pitch}
	_apply()


func go_home() -> void:
	if _home.is_empty():
		return
	target = _home["t"]
	distance = _home["d"]
	yaw = _home["y"]
	pitch = _home["p"]
	_apply()


func _apply() -> void:
	distance = clampf(distance, MIN_DIST, MAX_DIST)
	pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
	var dir := Vector3(cos(pitch) * cos(yaw), sin(pitch), cos(pitch) * sin(yaw))
	position = target + dir * distance
	look_at(target, Vector3.UP)


func _orbit(rel: Vector2) -> void:
	yaw -= rel.x * 0.006
	pitch += rel.y * 0.006
	_apply()


##
## Pan in the camera's own ground plane, scaled by distance so the drag keeps
## up with the view at every zoom level. Kept inside the field's bounds plus a
## margin, because a camera panned into the void is the same problem as one
## under the floor.
##
func _pan(rel: Vector2, extent: Vector2) -> void:
	var k := distance * 0.0016
	var right := Vector3(-sin(yaw), 0, cos(yaw))
	var fwd := Vector3(-cos(yaw), 0, -sin(yaw))
	target += (-right * rel.x + fwd * rel.y) * k
	target.x = clampf(target.x, -20.0, extent.x + 20.0)
	target.z = clampf(target.z, -20.0, extent.y + 20.0)
	_apply()


var field_extent := Vector2(225.0, 130.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					distance *= 0.88
					_apply()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					distance /= 0.88
					_apply()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			_pan(mm.relative, field_extent)
		elif _orbiting:
			_orbit(mm.relative)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		_pinch_dist = 0.0
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			var keys := _touches.keys()
			var a: Vector2 = _touches[keys[0]]
			var b: Vector2 = _touches[keys[1]]
			var d := a.distance_to(b)
			if _pinch_dist > 0.0:
				distance *= _pinch_dist / maxf(d, 1.0)
				_pan(sd.relative * 0.5, field_extent)
			_pinch_dist = d
			_apply()
		else:
			_orbit(sd.relative)
