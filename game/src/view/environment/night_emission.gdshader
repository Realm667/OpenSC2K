shader_type canvas_item;
render_mode unshaded;
uniform sampler2D emission : source_color, filter_nearest, repeat_disable;
uniform bool has_emission = false;
uniform float artwork_animation_seconds = 0.0;
varying flat float building_emission;
varying flat vec3 animation;
varying flat float grid;
void vertex() {
	vec4 bytes = round(COLOR * 255.0);
	float tag = bytes.r;
	building_emission = float(tag < 128.0 || tag == 255.0);
	if (building_emission < 0.5) tag -= 128.0;
	animation = vec3(1.0, 8.0, 0.0);
	if (tag == 64.0 || tag == 65.0) animation = vec3(bytes.g, tag == 65.0 ? 5.0 : 8.0, bytes.b * 256.0 + bytes.a);
	grid = float(tag == 48.0 || tag == 52.0);
}
void fragment() {
	// Grid/pipe overlays have special UVs and must not erase the building mask.
	if (grid > 0.5) discard;
	float frame = mod(floor(artwork_animation_seconds * animation.y), max(animation.x, 1.0));
	vec2 uv = UV + vec2(0.0, frame * animation.z) * TEXTURE_PIXEL_SIZE;
	vec4 surface = texture(TEXTURE, uv);
	vec4 light = has_emission ? texture(emission, uv) : vec4(0.0);
	// Opaque unlit foreground pixels erase lights behind them in painter order.
	COLOR = vec4(light.rgb * light.a * building_emission, surface.a);
}
