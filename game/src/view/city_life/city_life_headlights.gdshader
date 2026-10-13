shader_type canvas_item;
render_mode blend_add;

uniform float night = 0.0;
uniform float interpolation = 1.0;
uniform bool encoded_surfaces = false;
uniform sampler2DArray surfaces : filter_nearest, repeat_disable;
uniform sampler2D headlight_data : filter_nearest, repeat_disable;
varying flat float layer;
varying flat vec2 vehicle_world;
varying flat vec2 forward;
varying flat float front;
varying flat float opacity;
varying flat vec2 world_origin;
varying flat vec4 receiver_rect;

vec4 decoded_receiver(ivec2 point) {
	ivec2 size = textureSize(surfaces, 0).xy;
	vec4 sample_value = texelFetch(surfaces, ivec3(clamp(point, ivec2(0), size - ivec2(1)), int(layer)), 0);
	vec3 bytes = round(sample_value.rgb * 255.0);
	vec2 coordinate = vec2(bytes.r * 16.0 + floor(bytes.g / 16.0), mod(bytes.g, 16.0) * 256.0 + bytes.b) / 512.0 - vec2(4.0) + world_origin;
	return vec4(coordinate * sample_value.a, 0.0, sample_value.a);
}

vec4 smooth_receiver(vec2 uv) {
	// Decode before interpolation: filtering packed RGB bytes corrupts carries
	// between coordinate channels. Alpha-weighting excludes empty road texels.
	vec2 point = uv * vec2(textureSize(surfaces, 0).xy) - vec2(0.5);
	ivec2 first = ivec2(floor(point));
	vec2 weight = fract(point);
	vec4 value = mix(mix(decoded_receiver(first), decoded_receiver(first + ivec2(1, 0)), weight.x),
		mix(decoded_receiver(first + ivec2(0, 1)), decoded_receiver(first + ivec2(1, 1)), weight.x), weight.y);
	value.rg /= max(value.a, 0.00001);
	return value;
}

void vertex() {
	layer = float(INSTANCE_ID);
	receiver_rect = texelFetch(headlight_data, ivec2(INSTANCE_ID, 2), 0);
	vec4 data = texelFetch(headlight_data, ivec2(INSTANCE_ID, 0), 0);
	vehicle_world = data.xy + texelFetch(headlight_data, ivec2(INSTANCE_ID, 1), 0).xy * (1.0 - interpolation);
	world_origin = texelFetch(headlight_data, ivec2(INSTANCE_ID, 1), 0).zw;
	int packed = int(data.z);
	int direction = packed % 8;
	forward = vec2(direction == 1 ? 1.0 : (direction == 3 ? -1.0 : 0.0),
		direction == 2 ? 1.0 : (direction == 0 ? -1.0 : 0.0));
	if (direction >= 4) {
		forward = vec2(direction < 6 ? 1.0 : -1.0,
			(direction == 5 || direction == 6) ? 1.0 : -1.0) * 0.7071067811865476;
	}
	front = float(3 + packed / 8);
	opacity = data.w;
}

void fragment() {
	// QuadMesh has the opposite vertical UV orientation to Sprite2D.
	vec2 receiver_uv = receiver_rect.xy + vec2(UV.x, 1.0 - UV.y) * receiver_rect.zw;
	vec4 road = texture(surfaces, vec3(receiver_uv, layer));
	if (encoded_surfaces) {
		road = smooth_receiver(receiver_uv);
	}
	vec2 relative = (road.rg - vehicle_world) * 16.0;
	float distance = dot(relative, forward) - front;
	float across = abs(dot(relative, vec2(-forward.y, forward.x)));
	float width = 1.1 + max(distance, 0.0) * 0.15;
	float strength = 0.0;
	if (road.a > 0.0 && distance >= 0.0 && distance < 22.0 && across < width) {
		strength = 0.38 * pow(1.0 - distance / 22.0, 1.2) * pow(1.0 - across / width, 0.7);
	}
	COLOR = vec4(vec3(1.0, 0.8902, 0.6275), strength * opacity * night * road.a);
}
