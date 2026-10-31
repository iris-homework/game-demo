extends RefCounted
## Artwork-space atmosphere: one material, no extra viewport or input surface.
const SHADER := preload("res://shaders/battle_atmosphere.gdshader")
const DEFAULTS := {
	"atmosphere_time":0.0, "motion_enabled":true,
	"fog_strength":0.0, "dust_strength":0.0, "light_strength":0.0,
	"ray_strength":0.0, "water_strength":0.0, "wind":0.5,
	"fog_color":Color(0.53,0.62,0.72), "dust_color":Color(0.80,0.87,0.92),
	"ray_color":Color(1.0,0.93,0.78), "ray_origin":Vector2(0.2,-0.15),
	"water_rect":Vector4.ZERO,
	"flicker_strength":0.0,
	"light_boxes":[Vector4.ZERO,Vector4.ZERO,Vector4.ZERO,Vector4.ZERO],
	"stream_strength":0.0,
	"stream_paths":[Vector4.ZERO,Vector4.ZERO,Vector4.ZERO],
	"stream_widths":Vector3.ZERO,
}

# Calibrated to the current artwork, in original-image UVs. Explicit regions keep
# the stronger lamp animation off sunset skies, walls and the combat floor.
const LIGHT_BOXES := {
	"pump":[Vector4(0.693,0.038,0.711,0.074),Vector4(0.851,0.025,0.871,0.069),Vector4(0.852,0.282,0.879,0.308),Vector4(0.944,0.282,0.973,0.311)],
	"hive":[Vector4(0.904,0.244,0.951,0.315),Vector4(0.137,0.347,0.155,0.388),Vector4(0.287,0.058,0.332,0.108),Vector4(0.791,0.040,0.834,0.102)],
	"alley":[Vector4(0.601,0.148,0.663,0.225),Vector4(0.083,0.224,0.113,0.250),Vector4(0.311,0.287,0.341,0.313),Vector4(0.828,0.349,0.861,0.378)],
	"hospital":[Vector4(0.062,0.180,0.139,0.224),Vector4(0.853,0.179,0.931,0.223),Vector4(0.300,0.342,0.315,0.384),Vector4(0.686,0.343,0.700,0.385)],
	"power":[Vector4(0.284,0.056,0.309,0.088),Vector4(0.482,0.001,0.524,0.035),Vector4(0.589,0.041,0.619,0.075),Vector4(0.853,0.102,0.876,0.128)],
	"hotel":[Vector4(0.891,0.060,0.916,0.224),Vector4(0.201,0.282,0.245,0.302),Vector4(0.367,0.282,0.408,0.301),Vector4(0.637,0.274,0.687,0.297)],
	"bar":[Vector4(0.343,0.351,0.358,0.423),Vector4(0.943,0.305,0.960,0.384),Vector4(0.161,0.317,0.198,0.343),Vector4(0.694,0.367,0.735,0.386)],
}

static func apply_to(scenery: TextureRect, place_id: String, ground_start: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	# Explicit defaults also support Godot's headless rendering backend.
	for key in DEFAULTS:
		material.set_shader_parameter(key, PackedVector4Array(DEFAULTS[key]) if key in ["light_boxes","stream_paths"] else DEFAULTS[key])
	material.set_meta("profile_id", place_id)
	material.set_shader_parameter("ground_start", ground_start)
	material.set_shader_parameter("art_aspect", scenery.texture.get_width() / float(scenery.texture.get_height()))
	var profile := {}
	match place_id:
		"port":
			profile = {"fog_strength":0.07, "dust_strength":0.12, "water_strength":1.0, "water_rect":Vector4(0.18,0.399,0.84,0.434), "fog_color":Color("b2d4e2"), "dust_color":Color("dcecf1")}
		"pump":
			profile = {"fog_strength":0.13, "dust_strength":0.22, "light_strength":0.13, "water_strength":1.0, "water_rect":Vector4(0.12,0.425,0.79,0.478), "fog_color":Color("869bbf"), "dust_color":Color("aabfda")}
		"garden":
			profile = {"fog_strength":0.035, "dust_strength":0.65, "ray_strength":0.065, "ray_origin":Vector2(0.78,-0.18), "dust_color":Color("efe8ae"), "fog_color":Color("bccfba"), "wind":0.7}
		"block5":
			profile = {"fog_strength":0.025, "dust_strength":0.35, "ray_strength":0.045, "ray_origin":Vector2(0.63,-0.15), "dust_color":Color("f2e2b4"), "wind":0.8}
		"hive":
			profile = {"fog_strength":0.085, "dust_strength":0.28, "light_strength":0.20, "fog_color":Color("858bab"), "dust_color":Color("a8cdd9")}
		"alley":
			profile = {"fog_strength":0.11, "dust_strength":0.24, "light_strength":0.23, "fog_color":Color("9890b5"), "dust_color":Color("c2b0dd"), "wind":0.45}
		"hotel":
			profile = {"fog_strength":0.045, "dust_strength":0.23, "light_strength":0.16, "dust_color":Color("eed9ae"), "fog_color":Color("8f94b1")}
		"bar":
			profile = {"fog_strength":0.055, "dust_strength":0.22, "light_strength":0.18, "dust_color":Color("dcb5c6"), "fog_color":Color("a88cac"), "wind":0.25}
		"church":
			profile = {"fog_strength":0.045, "dust_strength":0.44, "light_strength":0.10, "ray_strength":0.11, "ray_origin":Vector2(0.22,-0.14), "dust_color":Color("cfddf7"), "ray_color":Color("a4bff4"), "wind":0.2}
		"tower":
			profile = {"fog_strength":0.02, "dust_strength":0.35, "ray_strength":0.09, "ray_origin":Vector2(0.12,-0.18), "dust_color":Color("f4e7c8"), "wind":0.25}
		"power":
			profile = {"fog_strength":0.09, "dust_strength":0.35, "light_strength":0.13, "dust_color":Color("e7b49a"), "fog_color":Color("8d9eae"), "wind":0.65}
		"junkyard":
			profile = {"fog_strength":0.10, "dust_strength":0.48, "light_strength":0.08, "dust_color":Color("dcb994"), "fog_color":Color("a99aa6"), "wind":0.9}
		"hospital":
			profile = {"fog_strength":0.035, "dust_strength":0.20, "light_strength":0.14, "dust_color":Color("9edee8"), "fog_color":Color("79b6c7"), "wind":0.15}
	for key in profile:
		material.set_shader_parameter(key, profile[key])
	if LIGHT_BOXES.has(place_id):
		material.set_shader_parameter("light_boxes", PackedVector4Array(LIGHT_BOXES[place_id]))
		material.set_shader_parameter("flicker_strength", 0.95)
	if place_id == "pump":
		material.set_shader_parameter("stream_paths", PackedVector4Array([
			Vector4(0.564,0.370,0.530,0.432),
			Vector4(0.663,0.345,0.615,0.437),
			Vector4(0.776,0.343,0.728,0.437)]))
		material.set_shader_parameter("stream_widths", Vector3(0.023,0.028,0.032))
		material.set_shader_parameter("stream_strength", 0.85)
	elif place_id == "garden":
		material.set_shader_parameter("stream_paths", PackedVector4Array([
			Vector4(0.390,0.355,0.390,0.421),Vector4.ZERO,Vector4.ZERO]))
		material.set_shader_parameter("stream_widths", Vector3(0.067,0.0,0.0))
		material.set_shader_parameter("stream_strength", 0.65)
	scenery.material = material
	return material

static func advance(scenery: TextureRect, delta: float) -> void:
	if not is_instance_valid(scenery) or not scenery.is_visible_in_tree(): return
	if scenery.get_tree().paused: return
	# Dummy has no real window and reports MINIMIZED even while a test is running.
	if DisplayServer.get_name() != "headless" and scenery.get_window().mode == Window.MODE_MINIMIZED: return
	var material := scenery.material as ShaderMaterial
	if material == null or material.shader != SHADER: return
	if not material.get_shader_parameter("motion_enabled"): return
	var elapsed: float = material.get_shader_parameter("atmosphere_time")
	material.set_shader_parameter("atmosphere_time", elapsed + clampf(delta, 0.0, 0.1))
