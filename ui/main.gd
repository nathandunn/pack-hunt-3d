extends Node3D
##
## The app: a 3D field, a setup drawer, and two modes.
##
## `single` plays one hunt back at 30 Hz under a fixed 45-degree camera. `simulate`
## runs N seeded hunts headless, sliced across frames so the browser tab never
## blocks, and shows the stats the handoff asks for — kill rate, mean chase
## length, energy at the outcome, and which gait decided it.
##
## The UI is built in code for the same reason war-sim-godot's is: it is one
## screen of controls that has to work on a phone and on a desktop without a
## second layout, and a hand-authored .tscn for that is a lot of coordinates to
## keep in sync with the code that reads them back.
##
## The "<- Apps" link is deliberately not here. It is a plain anchor in the
## export shell (`web/shell.html`), so it is a real link with real
## middle-click/long-press behaviour, and it is on screen while the WASM module
## is still downloading. The top bar keeps its left edge clear for it.
##

const World := preload("res://scripts/world.gd")
const Batch := preload("res://scripts/batch.gd")
const Data := preload("res://scripts/data.gd")
const Energy := preload("res://scripts/energy.gd")
const Field := preload("res://ui/field.gd")
const Cam := preload("res://ui/camera.gd")
const Palette := preload("res://scripts/palette.gd")

const BACK_LINK_GUTTER := 118.0
const TOP_BAR_H := 46.0
const DRAWER_W := 360.0
const SIM_SLICE_MS := 9.0
const MAX_CATCHUP := 4

const WOLF_TRAITS := ["aggression", "caution", "cooperation", "patience", "risk", "focus",
	"persistence", "cohesion"]
const DEER_TRAITS := ["aggression", "caution", "cooperation", "patience", "risk", "focus",
	"vigilance", "panic", "herdCohesion", "stamina"]

var _wolf_p: Data.Personality
var _deer_p: Data.Personality
var _n_wolves := 5
var _n_deer := 1
var _seed := 20260910
var _cfg := {}

var _mode := "single"
var _frames: Array = []
var _result := {}
var _cursor := 0.0
var _playing := true
var _speed := 1.0

var _sim_active := false
var _sim_trials := 200
var _sim_stats: Batch.Stats
var _sim_index := 0

var _field: Node3D
var _cam: Camera3D
var _ui: CanvasLayer
var _drawer: PanelContainer
var _drawer_open := false
var _scrim: ColorRect
var _stats: RichTextLabel
var _hud: Label
var _play_btn: Button
var _mode_btn: Button
var _setup_btn: Button
var _scrub: HSlider
var _sim_bar: ProgressBar
var _sim_panel: PanelContainer
var _trait_sliders := {}
var _energy_sliders := {}
var _sustain: Label
var _scrub_guard := false


func _ready() -> void:
	Energy.build()
	var arch := Data.archetypes()
	_wolf_p = arch["teamplayer"]
	_deer_p = arch["defender"]
	_cfg = {"wolf": Energy.field_data(Energy.WOLF), "deer": Energy.field_data(Energy.DEER)}

	_field = Field.new()
	add_child(_field)

	_cam = Cam.new()
	_cam.far = 900.0
	add_child(_cam)
	_cam.field_extent = Vector2(Field.FIELD_M_W, Field.FIELD_M_H)
	# fixed 45 degrees, on the herd: the deer starts on the right and the pack
	# is in the middle, so the interesting half is the right two-thirds
	_cam.setup(Vector3(Field.FIELD_M_W * 0.58, 0, Field.FIELD_M_H * 0.5), 150.0)

	_build_ui()
	_run_hunt()


# ── UI ────────────────────────────────────────────────────────────
func _theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var btn := StyleBoxFlat.new()
	btn.bg_color = Palette.UI_BUTTON
	btn.border_color = Palette.UI_BORDER
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(7)
	btn.content_margin_left = 12
	btn.content_margin_right = 12
	btn.content_margin_top = 7
	btn.content_margin_bottom = 7
	var hov := btn.duplicate() as StyleBoxFlat
	hov.bg_color = Palette.UI_BUTTON_HOVER
	var prs := btn.duplicate() as StyleBoxFlat
	prs.bg_color = Palette.UI_BUTTON_PRESSED
	for cls: String in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, hov)
		t.set_stylebox("pressed", cls, prs)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, Palette.UI_TEXT)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(Palette.UI_PANEL, 0.95)
	panel.border_color = Palette.UI_BORDER_SOFT
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(12)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_color("font_color", "Label", Palette.UI_TEXT)
	t.set_color("default_color", "RichTextLabel", Palette.UI_TEXT)
	return t


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	_ui.add_child(root)

	# top bar — left edge kept clear for the shell's "<- Apps" pill
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = BACK_LINK_GUTTER
	bar.offset_right = -10
	bar.offset_top = 8
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)

	var title := Label.new()
	title.text = "PACK HUNT 3D"
	title.add_theme_font_size_override("font_size", 17)
	bar.add_child(title)
	bar.add_child(_spacer())

	_mode_btn = _button("Mode: single", _toggle_mode)
	bar.add_child(_mode_btn)
	_play_btn = _button("Pause", _toggle_play)
	bar.add_child(_play_btn)
	bar.add_child(_button("Step", func() -> void:
		_playing = false
		_play_btn.text = "Play"
		_set_cursor(floorf(_cursor) + 1.0)))
	bar.add_child(_button("Speed 1x", _cycle_speed))
	bar.add_child(_button("Home view", func() -> void: _cam.go_home()))
	bar.add_child(_button("Roll seed", func() -> void:
		_seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF
		_run_hunt()))
	bar.add_child(_button("Run", _run_hunt))
	_setup_btn = _button("Setup", _toggle_drawer)
	bar.add_child(_setup_btn)

	# scrub
	var scrub_row := HBoxContainer.new()
	scrub_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	scrub_row.offset_left = 12
	scrub_row.offset_right = -12
	scrub_row.offset_top = -46
	scrub_row.offset_bottom = -12
	root.add_child(scrub_row)
	_scrub = HSlider.new()
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.min_value = 0
	_scrub.max_value = 1
	_scrub.step = 1
	_scrub.value_changed.connect(func(v: float) -> void:
		if _scrub_guard:
			return
		_playing = false
		_play_btn.text = "Play"
		_set_cursor(v))
	scrub_row.add_child(_scrub)

	# HUD, bottom left
	_hud = Label.new()
	_hud.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hud.offset_left = 14
	_hud.offset_top = -84
	_hud.add_theme_font_size_override("font_size", 13)
	root.add_child(_hud)

	# result / stats panel, top right under the bar
	_sim_panel = PanelContainer.new()
	_sim_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_sim_panel.offset_left = -400
	_sim_panel.offset_right = -10
	_sim_panel.offset_top = TOP_BAR_H + 6
	root.add_child(_sim_panel)
	var box := VBoxContainer.new()
	_sim_panel.add_child(box)
	_sim_bar = ProgressBar.new()
	_sim_bar.visible = false
	_sim_bar.custom_minimum_size = Vector2(0, 10)
	box.add_child(_sim_bar)
	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.fit_content = true
	_stats.custom_minimum_size = Vector2(376, 0)
	_stats.scroll_active = false
	box.add_child(_stats)

	_build_drawer(root)


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _build_drawer(root: Control) -> void:
	_scrim = ColorRect.new()
	_scrim.color = Palette.UI_SCRIM
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.visible = false
	_scrim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_toggle_drawer())
	root.add_child(_scrim)

	_drawer = PanelContainer.new()
	_drawer.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_drawer.offset_left = -DRAWER_W
	_drawer.offset_top = 0
	_drawer.offset_bottom = 0
	_drawer.visible = false
	root.add_child(_drawer)

	var scroll := ScrollContainer.new()
	_drawer.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size = Vector2(DRAWER_W - 34, 0)
	scroll.add_child(col)

	col.add_child(_heading("Wolves"))
	col.add_child(_preset_picker(true))
	for t: String in WOLF_TRAITS:
		col.add_child(_trait_row(true, t))
	col.add_child(_count_row(true))

	col.add_child(_heading("Deer"))
	col.add_child(_preset_picker(false))
	for t: String in DEER_TRAITS:
		col.add_child(_trait_row(false, t))
	col.add_child(_count_row(false))

	col.add_child(_heading("Energy & gaits"))
	var note := Label.new()
	note.text = "Derived in specs/pack-hunt-energy.md from grey wolf and white-tailed deer field figures. Cost is energy per second; a full tank is 1.0."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	col.add_child(note)
	for sp: int in [Energy.WOLF, Energy.DEER]:
		var lbl := Label.new()
		lbl.text = "  wolf" if sp == Energy.WOLF else "  deer"
		col.add_child(lbl)
		for key: String in ["max_energy", "sprint_cost", "gallop_cost", "recovery_rate", "fatigue_threshold"]:
			col.add_child(_energy_row(sp, key))
	_sustain = Label.new()
	_sustain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sustain.add_theme_font_size_override("font_size", 12)
	col.add_child(_sustain)
	col.add_child(_button("Reset to field data", func() -> void:
		_cfg["wolf"] = Energy.field_data(Energy.WOLF)
		_cfg["deer"] = Energy.field_data(Energy.DEER)
		for k: String in _energy_sliders:
			var parts: Array = k.split("|")
			var s = _cfg["wolf"] if int(parts[0]) == Energy.WOLF else _cfg["deer"]
			_energy_sliders[k].set_value_no_signal(s.get(parts[1]))
		_update_sustain()))
	_update_sustain()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	return l


func _preset_picker(wolf: bool) -> OptionButton:
	var ob := OptionButton.new()
	var keys := Data.archetypes().keys()
	for k: String in keys:
		ob.add_item(k)
	ob.selected = keys.find("teamplayer" if wolf else "defender")
	ob.item_selected.connect(func(i: int) -> void:
		var p: Data.Personality = Data.archetypes()[keys[i]]
		if wolf:
			_wolf_p = p
		else:
			_deer_p = p
		for t: String in (WOLF_TRAITS if wolf else DEER_TRAITS):
			var key := ("w|" if wolf else "d|") + t
			if _trait_sliders.has(key):
				_trait_sliders[key].set_value_no_signal(p.get_trait(t))
		_run_hunt())
	return ob


func _trait_row(wolf: bool, t: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = t
	l.custom_minimum_size = Vector2(112, 0)
	l.add_theme_font_size_override("font_size", 12)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = (_wolf_p if wolf else _deer_p).get_trait(t)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := Label.new()
	v.custom_minimum_size = Vector2(38, 0)
	v.add_theme_font_size_override("font_size", 12)
	v.text = "%.2f" % s.value
	s.value_changed.connect(func(val: float) -> void:
		v.text = "%.2f" % val
		var p := _wolf_p if wolf else _deer_p
		p.traits[t] = val)
	s.drag_ended.connect(func(changed: bool) -> void:
		if changed:
			_run_hunt())
	row.add_child(s)
	row.add_child(v)
	_trait_sliders[("w|" if wolf else "d|") + t] = s
	return row


func _count_row(wolf: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "count"
	l.custom_minimum_size = Vector2(112, 0)
	l.add_theme_font_size_override("font_size", 12)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 1
	s.max_value = 50 if wolf else 50
	s.step = 1
	s.value = _n_wolves if wolf else _n_deer
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := Label.new()
	v.custom_minimum_size = Vector2(38, 0)
	v.add_theme_font_size_override("font_size", 12)
	v.text = str(int(s.value))
	s.value_changed.connect(func(val: float) -> void:
		v.text = str(int(val))
		if wolf:
			_n_wolves = int(val)
		else:
			_n_deer = int(val))
	s.drag_ended.connect(func(changed: bool) -> void:
		if changed:
			_run_hunt())
	row.add_child(s)
	row.add_child(v)
	return row


func _energy_row(sp: int, key: String) -> HBoxContainer:
	var ranges := {
		"max_energy": [0.1, 2.0, 0.05],
		"sprint_cost": [0.0, 0.3, 0.002],
		"gallop_cost": [-0.02, 0.08, 0.0005],
		"recovery_rate": [0.0, 0.05, 0.0002],
		"fatigue_threshold": [0.0, 1.0, 0.05],
	}
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = key
	l.custom_minimum_size = Vector2(126, 0)
	l.add_theme_font_size_override("font_size", 12)
	row.add_child(l)
	var s := HSlider.new()
	var r: Array = ranges[key]
	s.min_value = r[0]
	s.max_value = r[1]
	s.step = r[2]
	var settings = _cfg["wolf"] if sp == Energy.WOLF else _cfg["deer"]
	s.value = settings.get(key)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := Label.new()
	v.custom_minimum_size = Vector2(58, 0)
	v.add_theme_font_size_override("font_size", 12)
	v.text = "%.4f" % s.value
	s.value_changed.connect(func(val: float) -> void:
		v.text = "%.4f" % val
		var st = _cfg["wolf"] if sp == Energy.WOLF else _cfg["deer"]
		st.set(key, val)
		_update_sustain())
	s.drag_ended.connect(func(changed: bool) -> void:
		if changed:
			_run_hunt())
	row.add_child(s)
	row.add_child(v)
	_energy_sliders["%d|%s" % [sp, key]] = s
	return row


func _update_sustain() -> void:
	if _sustain == null:
		return
	var f := func(sp: int, c: float) -> String:
		var st = _cfg["wolf"] if sp == Energy.WOLF else _cfg["deer"]
		return "inf" if c <= 0.0 else "%.0fs" % (st.max_energy / c)
	_sustain.text = "a full tank lasts: wolf sprint %s, gallop %s · deer sprint %s, gallop %s, bound %s" % [
		f.call(Energy.WOLF, _cfg["wolf"].sprint_cost), f.call(Energy.WOLF, _cfg["wolf"].gallop_cost),
		f.call(Energy.DEER, _cfg["deer"].sprint_cost), f.call(Energy.DEER, _cfg["deer"].gallop_cost),
		f.call(Energy.DEER, Energy.cost[Energy.DEER][Energy.BOUND])]


func _toggle_drawer() -> void:
	_drawer_open = not _drawer_open
	_drawer.visible = _drawer_open
	_scrim.visible = _drawer_open
	_setup_btn.text = "Close" if _drawer_open else "Setup"


func _toggle_play() -> void:
	_playing = not _playing
	_play_btn.text = "Pause" if _playing else "Play"


func _cycle_speed() -> void:
	_speed = 1.0 if _speed >= 4.0 else _speed * 2.0
	for c: Node in _ui.get_child(0).get_child(0).get_children():
		if c is Button and (c as Button).text.begins_with("Speed"):
			(c as Button).text = "Speed %dx" % int(_speed)


func _toggle_mode() -> void:
	_mode = "simulate" if _mode == "single" else "single"
	_mode_btn.text = "Mode: " + _mode
	if _mode == "simulate":
		_start_sim()
	else:
		_sim_active = false
		_sim_bar.visible = false
		_run_hunt()


# ── running ───────────────────────────────────────────────────────
func _run_hunt() -> void:
	if _mode == "simulate":
		_start_sim()
		return
	_frames = []
	_result = World.run_hunt(_wolf_p, _deer_p, _n_wolves, _n_deer, _seed,
		World.MAX_TICKS, _frames, _cfg)
	_field.set_frames(_frames)
	_scrub_guard = true
	_scrub.max_value = maxf(1.0, float(_frames.size() - 1))
	_scrub_guard = false
	_set_cursor(0.0)
	_playing = true
	_play_btn.text = "Pause"
	_show_result()


func _set_cursor(c: float) -> void:
	_cursor = clampf(c, 0.0, maxf(0.0, float(_frames.size() - 1)))
	_field.set_cursor(_cursor)
	_scrub_guard = true
	_scrub.value = _cursor
	_scrub_guard = false
	_update_hud()


func _start_sim() -> void:
	_sim_stats = Batch.Stats.new()
	_sim_index = 0
	_sim_active = true
	_sim_bar.visible = true
	_sim_bar.max_value = _sim_trials
	_sim_bar.value = 0


func _process(delta: float) -> void:
	if _sim_active:
		var t0 := Time.get_ticks_usec()
		while _sim_index < _sim_trials and float(Time.get_ticks_usec() - t0) / 1000.0 < SIM_SLICE_MS:
			Batch.run_slice(_sim_stats, _wolf_p, _deer_p, _n_wolves, _n_deer,
				_sim_index, _sim_index + 1, _seed, _cfg)
			_sim_index += 1
		_sim_bar.value = _sim_index
		_show_sim()
		if _sim_index >= _sim_trials:
			_sim_active = false
		return
	if _playing and not _frames.is_empty():
		var next := _cursor + delta * Energy.TICKS_PER_SEC * _speed
		# a slow frame drops sim time rather than running away with it
		next = minf(next, _cursor + float(MAX_CATCHUP) * _speed)
		if next >= float(_frames.size() - 1):
			next = float(_frames.size() - 1)
			_playing = false
			_play_btn.text = "Play"
		_set_cursor(next)


func _update_hud() -> void:
	if _frames.is_empty():
		_hud.text = ""
		return
	var f: Dictionary = _frames[clampi(int(_cursor), 0, _frames.size() - 1)]
	var counts := {}
	var pack_e := 0.0
	for w: Dictionary in f["wolves"]:
		var g: String = Energy.GAIT_NAMES[w["gait"]]
		counts[g] = counts.get(g, 0) + 1
		pack_e += w["energy"]
	pack_e /= float(maxi(f["wolves"].size(), 1))
	var mix := []
	for k: String in counts:
		mix.push_back("%sx%d" % [k, counts[k]])
	var deer_e := []
	var alive := 0
	for d: Dictionary in f["deer"]:
		if d["alive"] and not d["escaped"]:
			alive += 1
			deer_e.push_back("%d%%" % int(round(d["energy"] * 100.0)))
	_hud.text = "%.1fs / %.1fs   seed %d\n%s   pack tank %d%%\ndeer %d running   tank %s" % [
		_cursor / Energy.TICKS_PER_SEC, float(_frames.size()) / Energy.TICKS_PER_SEC, _seed,
		" ".join(mix), int(round(pack_e * 100.0)), alive, " ".join(deer_e)]


func _show_result() -> void:
	if _result.is_empty():
		return
	var deer_win: bool = _result["winner"] == "deer"
	var head := "[color=%s]ESCAPED[/color]" % Palette.GOAL.to_html(false) if deer_win \
			else "[color=%s]CAUGHT[/color]" % Palette.DEAD.to_html(false)
	if deer_win and _result["capped"]:
		head = "[color=%s]SURVIVED[/color] (the pack ran out the backstop)" % Palette.GOAL.to_html(false)
	_stats.text = "[b]%s[/b]  in %.1fs\ndecided by [b]%s[/b] · chase %.1fs\ndeer tank at the end %d%% · pack tank %d%%\n\n[color=%s]drag to pan · wheel or pinch to zoom · the view is fixed at 45°[/color]" % [
		head, float(_result["ticks"]) / Energy.TICKS_PER_SEC, _result["decided_by"],
		float(_result["chase_ticks"]) / Energy.TICKS_PER_SEC,
		int(round(_result["deer_energy"] * 100.0)), int(round(_result["wolf_energy"] * 100.0)),
		Palette.UI_MUTED.to_html(false)]


func _show_sim() -> void:
	var s := _sim_stats
	if s.n == 0:
		return
	var wg := s.gait_share(s.wolf_gait)
	var dg := s.gait_share(s.deer_gait)
	var keys := s.decided.keys()
	keys.sort()
	var by := []
	for k: String in keys:
		by.push_back("%s %d%%" % [k, int(round(100.0 * float(s.decided[k]) / float(s.n)))])
	_stats.text = ("[b]Simulate[/b] %d / %d hunts\n" % [s.n, _sim_trials]) \
		+ "kill rate [b]%.1f%%[/b] · mean hunt [b]%.1fs[/b] · mean chase [b]%.1fs[/b]\n" % [
			s.kill_rate() * 100.0, float(s.ticks) / float(s.n) / Energy.TICKS_PER_SEC,
			float(s.chase) / float(s.n) / Energy.TICKS_PER_SEC] \
		+ "energy at the outcome — deer [b]%d%%[/b], pack [b]%d%%[/b]\n" % [
			int(round(s.deer_e / float(s.n) * 100.0)), int(round(s.wolf_e / float(s.n) * 100.0))] \
		+ "[color=%s]decided by: %s[/color]\n" % [Palette.UI_MUTED.to_html(false), " · ".join(by)] \
		+ "[color=" + Palette.WOLF.to_html(false) + "]wolf[/color] walk %.0f%% trot %.0f%% gallop %.0f%% sprint %.0f%%\n" % [
			wg[0] * 100.0, wg[1] * 100.0, wg[2] * 100.0, wg[3] * 100.0] \
		+ "[color=" + Palette.DEER.to_html(false) + "]deer[/color] trot %.0f%% gallop %.0f%% sprint %.0f%% bound %.0f%% stot %.0f%%" % [
			dg[1] * 100.0, dg[2] * 100.0, dg[3] * 100.0, dg[4] * 100.0, dg[5] * 100.0]
