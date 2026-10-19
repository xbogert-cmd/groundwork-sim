extends Control
## Bucket gauge, swamp meter and help text.

var fill := 0.0 ## 0..1
var fill_m3 := 0.0
var capacity := 1.4
var swamp := 1.0 ## fraction of swamp water left
var water_m3 := 0.0
var reach_ok := true
var message := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var vs := size
	# --- bucket gauge (bottom right)
	var gx := vs.x - 150.0
	var gy := vs.y - 230.0
	draw_rect(Rect2(gx - 14, gy - 40, 124, 218), Color(0, 0, 0, 0.45), true)
	draw_string(font, Vector2(gx, gy - 16), "BUCKET", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.85, 0.3))
	var bar := Rect2(gx, gy, 52, 150)
	draw_rect(bar, Color(0.1, 0.1, 0.1, 0.8), true)
	var fh := bar.size.y * clampf(fill, 0.0, 1.0)
	var col := Color(0.55, 0.36, 0.2)
	if fill > 0.95:
		col = Color(0.9, 0.3, 0.2)
	draw_rect(Rect2(bar.position.x, bar.end.y - fh, bar.size.x, fh), col, true)
	for k in 5:
		var yy := bar.position.y + bar.size.y * k / 4.0
		draw_line(Vector2(bar.position.x, yy), Vector2(bar.end.x + 8, yy), Color(1, 1, 1, 0.5), 2.0)
	draw_rect(bar, Color(1, 0.85, 0.3), false, 3.0)
	draw_string(font, Vector2(gx + 62, gy + 20), "%.1f" % fill_m3, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(gx + 62, gy + 40), "of %.1f m³" % capacity, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
	if fill > 0.97:
		draw_string(font, Vector2(gx + 62, gy + 80), "FULL", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.4, 0.3))

	# --- swamp meter (top left)
	draw_rect(Rect2(16, 16, 330, 84), Color(0, 0, 0, 0.45), true)
	draw_string(font, Vector2(30, 42), "GROUNDWORK SIM", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.85, 0.3))
	draw_string(font, Vector2(30, 66), "Swamp water left: %d%%  (%.0f m³)" % [roundi(swamp * 100.0), water_m3], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	var wb := Rect2(30, 76, 300, 12)
	draw_rect(wb, Color(0.1, 0.1, 0.1, 0.8), true)
	draw_rect(Rect2(wb.position, Vector2(wb.size.x * clampf(swamp, 0.0, 1.0), wb.size.y)), Color(0.3, 0.65, 0.75), true)

	var help := "W/S drive   A/D turn   Mouse aim   LMB dig   RMB dump   Q/E orbit   Wheel zoom   R reset   U rain"
	draw_string(font, Vector2(16, vs.y - 18), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.85))
	if message != "":
		draw_string(font, Vector2(0, vs.y * 0.18), message, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 26, Color(1, 0.9, 0.5))
