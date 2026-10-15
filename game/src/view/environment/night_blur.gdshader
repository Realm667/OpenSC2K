shader_type canvas_item;
render_mode unshaded;
uniform vec2 direction = vec2(1.0, 0.0);
uniform float radius = 1.0;
uniform float small_light_retention = 0.0;
void fragment() {
	vec2 step_uv = TEXTURE_PIXEL_SIZE * direction * radius;
	vec3 color = texture(TEXTURE, UV).rgb * 0.227027;
	color += (texture(TEXTURE, UV + step_uv * 1.384615).rgb + texture(TEXTURE, UV - step_uv * 1.384615).rgb) * 0.316216;
	color += (texture(TEXTURE, UV + step_uv * 3.230769).rgb + texture(TEXTURE, UV - step_uv * 3.230769).rgb) * 0.070270;
	// Thin master-art windows occupy only a fraction of a blur sample. Retain
	// a bounded local peak before the second (vertical) pass; broad lit surfaces
	// keep their existing energy, and no extra viewport or draw pass is needed.
	if (small_light_retention > 0.0) {
		vec3 peak = texture(TEXTURE, UV).rgb;
		peak = max(peak, texture(TEXTURE, UV + vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).rgb);
		peak = max(peak, texture(TEXTURE, UV - vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).rgb);
		peak = max(peak, texture(TEXTURE, UV + vec2(0.0, TEXTURE_PIXEL_SIZE.y)).rgb);
		peak = max(peak, texture(TEXTURE, UV - vec2(0.0, TEXTURE_PIXEL_SIZE.y)).rgb);
		color = max(color, peak * small_light_retention);
	}
	COLOR = vec4(color, 1.0);
}
