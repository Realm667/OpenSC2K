shader_type canvas_item;
render_mode unshaded;

uniform sampler2D city_screen : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength : hint_range(0.0, 1.0) = 0.25;
uniform float edge_size : hint_range(0.05, 0.45) = 0.28;
uniform float transition : hint_range(0.05, 1.0) = 0.75;

void fragment() {
	float edge_distance = min(UV.y, 1.0 - UV.y);
	float amount = 1.0 - smoothstep(edge_size * (1.0 - transition), edge_size, edge_distance);
	// Derivatives express the local map rectangle in viewport UVs, also when
	// UI scaling or window resizing changes its actual screen size.
	vec2 extent = SCREEN_PIXEL_SIZE / max(fwidth(UV), vec2(0.000001));
	if (amount <= 0.0 || strength <= 0.0) discard;
	vec2 lo = SCREEN_UV - UV * extent + SCREEN_PIXEL_SIZE * 0.5;
	vec2 hi = lo + extent - SCREEN_PIXEL_SIZE;
	vec2 step_uv = SCREEN_PIXEL_SIZE * (1.5 * strength * amount);
	vec3 blurred = vec3(0.0);
	// Paired bilinear taps approximate a 9x9 Gaussian with 25 texture reads.
	// Avoid widely spaced taps that repeat the pixel grid at strong settings.
	// Clamp to the map so adjacent toolbars never bleed in. No mipmap cost.
	for (int y = -2; y <= 2; y++) {
		float wy = y == 0 ? 0.2270270270 : (abs(y) == 1 ? 0.3162162162 : 0.0702702703);
		float oy = float(sign(y)) * (abs(y) == 1 ? 1.3846153846 : 3.2307692308);
		for (int x = -2; x <= 2; x++) {
			float wx = x == 0 ? 0.2270270270 : (abs(x) == 1 ? 0.3162162162 : 0.0702702703);
			float ox = float(sign(x)) * (abs(x) == 1 ? 1.3846153846 : 3.2307692308);
			blurred += texture(city_screen, clamp(SCREEN_UV + vec2(ox, oy) * step_uv, lo, hi)).rgb * wx * wy;
		}
	}
	COLOR = vec4(blurred, 1.0);
}
