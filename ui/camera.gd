extends Camera3D
##
## Fixed 45-degree camera over the herd, with pan and zoom.
##
##   mouse   drag pans, wheel zooms
##   touch   one finger pans, two fingers pinch to zoom
##
## **There is no orbit.** The build had one and it was the wrong control for
## this app on a phone: the interesting thing on the field is a chase across a
## 225 m plain, and every orbit gesture traded a legible view of it for a view
## from somewhere the user then had to get back from. A one-finger drag that
## spins the world is also the same gesture as the one-finger drag that ought to
## move the map, so the pan most people were reaching for was unreachable.
##
## The elevation and the heading are therefore constants, not variables, and the
## orbit handlers are gone rather than disabled — `tests.gd` asserts that this
## script exposes no way to change either, so "we only hid it" cannot come back
## by accident.
##
## Looking down the +X axis at 45 degrees puts the deer's goal — the left edge
## of the field — at the top of the screen and the pack between it and the
## viewer, which is the composition the simulation is about.
##

## Elevation above the horizontal. Fixed.
const PITCH := deg_to_rad(45.0)
## Compass heading of the eye about the target. Fixed.
const YAW := deg_to_rad(-90.0)

const MIN_DIST := 12.0
const MAX_DIST := 340.0

var target := Vector3.ZERO
var distance := 150.0

var _panning := false
var _touches := {}
var _pinch_dist := 0.0
var _home := {}

var field_extent := Vector2(225.0, 130.0)


func setup(centre: Vector3, dist: float) -> void:
	target = centre
	distance = dist
	_home = {"t": centre, "d": dist}
	_apply()


func go_home() -> void:
	if _home.is_empty():
		return
	target = _home["t"]
	distance = _home["d"]
	_apply()


func _apply() -> void:
	distance = clampf(distance, MIN_DIST, MAX_DIST)
	var dir := Vector3(cos(PITCH) * cos(YAW), sin(PITCH), cos(PITCH) * sin(YAW))
	# `look_at_from_position` rather than `position =` + `look_at`, because the
	# second needs the node to be inside the tree and `tests.gd` drives this
	# camera standing on its own.
	look_at_from_position(target + dir * distance, target, Vector3.UP)


##
## Pan in the ground plane, scaled by distance so the drag keeps up with the
## view at every zoom level. Kept inside the field's bounds plus a margin,
## because a camera panned into the void is a camera nobody can recover.
##
func _pan(rel: Vector2, extent: Vector2) -> void:
	var k := distance * 0.0016
	var right := Vector3(-sin(YAW), 0, cos(YAW))
	var fwd := Vector3(-cos(YAW), 0, -sin(YAW))
	target += (-right * rel.x + fwd * rel.y) * k
	target.x = clampf(target.x, -20.0, extent.x + 20.0)
	target.z = clampf(target.z, -20.0, extent.y + 20.0)
	_apply()


func _zoom(factor: float) -> void:
	distance *= factor
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom(0.88)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom(1.0 / 0.88)
	elif event is InputEventMouseMotion:
		if _panning:
			_pan((event as InputEventMouseMotion).relative, field_extent)
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
			_pinch_dist = d
			# two fingers moving together still pan, at half weight so the
			# pinch is not fighting the drag
			_pan(sd.relative * 0.5, field_extent)
		else:
			_pan(sd.relative, field_extent)
