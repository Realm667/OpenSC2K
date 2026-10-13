// Texel pages preserve the existing atlas coordinates and painter order.
#ifdef USE_PAGED_ATLAS
uniform float region_atlas_edge = 2048.0;
uniform sampler2DArray region_atlas_pages : filter_nearest, repeat_disable;
uniform sampler2DArray region_emission_pages : source_color, filter_nearest, repeat_disable;
uniform sampler2DArray region_season_pages : filter_nearest, repeat_disable;

vec4 region_page_texel(sampler2DArray pages, vec2 texel) {
	ivec2 pixel = clamp(ivec2(floor(texel)), ivec2(0), ivec2(int(region_atlas_edge) - 1));
	ivec2 page = pixel / 1024;
	int layer = page.y * ((int(region_atlas_edge) + 1023) / 1024) + page.x;
	return texelFetch(pages, ivec3(pixel % 1024, layer), 0);
}

vec4 region_page_sample(sampler2DArray pages, vec2 uv) {
	return region_page_texel(pages, uv * region_atlas_edge);
}
#endif
