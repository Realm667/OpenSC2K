// Actual terrain altitude, carried once per ground quad in world coordinates.
uniform bool terrain_elevation_enabled = false;
uniform vec2 terrain_elevation_range = vec2(0.0, 31.0);
varying flat float terrain_elevation;

vec3 terrain_elevation_color(vec3 color, float coverage) {
	if (!terrain_elevation_enabled || terrain_elevation < 0.0 || dark_underground) {
		return color;
	}
	// A shared map-wide range keeps the tone stable across zoom and region edges.
	// Multiplication preserves the hue of the selected artwork and season.
	float position = (terrain_elevation - terrain_elevation_range.x) / max(8.0, terrain_elevation_range.y - terrain_elevation_range.x);
	float brightness = mix(0.88, 1.12, clamp(position, 0.0, 1.0));
	return color * mix(1.0, brightness, clamp(coverage, 0.0, 1.0));
}
