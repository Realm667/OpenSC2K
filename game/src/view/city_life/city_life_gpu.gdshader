shader_type canvas_item;
render_mode unshaded;
#include "res://src/view/environment/environment_color.gdshaderinc"
#include "res://src/view/clouds/cloud_field.gdshaderinc"
uniform sampler2D artwork : source_color, filter_nearest, repeat_disable;
uniform sampler2D lamps : source_color, filter_nearest, repeat_disable;
uniform sampler2D parameters : filter_nearest, repeat_disable;
uniform sampler2DArray masks : filter_nearest, repeat_disable;
uniform float interpolation = 1.0;
uniform float artwork_scale = 1.0;
uniform bool emission_only = false;
uniform bool vehicle_has_emission = false;
varying flat float slot;
varying flat float mask_layer;
varying vec2 sprite_pixel;
varying flat vec4 source_rect;
varying vec2 world_pixel;
varying vec2 cloud_ground_grid;
varying flat vec2 mask_origin;
varying flat float opacity;
void vertex() {
	slot = float(INSTANCE_ID);
	vec4 rect = texelFetch(parameters, ivec2(int(slot), 0), 0);
	vec4 world = texelFetch(parameters, ivec2(int(slot), 1), 0);
	vec4 mask = texelFetch(parameters, ivec2(int(slot), 2), 0);
	vec2 shift = round(world.zw * (1.0 - interpolation));
	// Extend the lower/right raster edge by one texel. The fragment clips it;
	// half-scale pixel centers on that edge must still sample the last texel.
	vec2 logical_size = rect.zw / artwork_scale;
	VERTEX = (VERTEX * (logical_size + vec2(1.0)) + shift) / logical_size;
	// QuadMesh vertical UVs run opposite to image rows.
	vec2 sprite_uv = vec2(UV.x, 1.0 - UV.y);
	world_pixel = world.xy + shift + sprite_uv * (logical_size + vec2(1.0));
	source_rect = rect;
	sprite_pixel = sprite_uv * (logical_size + vec2(1.0));
	mask_origin = mask.xy;
	mask_layer = mask.z;
	opacity = mask.w;
	cloud_ground_grid = cloud_grid_at((MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy);
}
void fragment() {
	// Match image-rectangle sampling at exact half-resolution texel boundaries.
	vec2 pixel = floor(sprite_pixel * artwork_scale - vec2(0.0001));
	if (any(lessThan(pixel, vec2(0.0))) || any(greaterThanEqual(pixel, source_rect.zw))) discard;
	vec2 source_uv = (source_rect.xy + pixel + vec2(0.5)) / vec2(textureSize(artwork, 0));
	vec4 color = texture(artwork, source_uv);
	if (color.a <= 0.0) discard;
	vec2 mask_uv = ((world_pixel - sprite_pixel + floor(pixel / artwork_scale)) - mask_origin + vec2(0.5)) / 128.0;
	if (all(greaterThanEqual(mask_uv, vec2(0.0))) && all(lessThan(mask_uv, vec2(1.0))) && texture(masks, vec3(mask_uv, mask_layer)).a > 0.0) discard;
	vec4 light = texture(lamps, source_uv);
	if (emission_only) {
		// Preserve the original emission pass: unlit opaque art covers rear lights.
		COLOR = vec4(light.rgb * light.a * opacity, color.a * opacity);
	} else {
		vec3 shaded = environment_color(cloud_shadow(color.rgb, cloud_ground_grid), source_uv);
		if (vehicle_has_emission && environment_enabled) shaded = mix(shaded, light.rgb, light.a * environment_night);
		COLOR = vec4(shaded, color.a * opacity);
	}
}
