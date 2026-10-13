// Actual terrain altitude, carried once per ground quad in world coordinates.
uniform bool terrain_elevation_enabled = false;
varying flat float terrain_elevation;

vec3 terrain_elevation_color(vec3 color, float coverage) {
	if (!terrain_elevation_enabled || terrain_elevation < 0.0 || dark_underground) {
		return color;
	}
	// A fixed map-wide range keeps the tone stable across zoom and region edges.
	// Multiplication preserves the hue of the selected artwork and season.
	float brightness = mix(0.88, 1.12, clamp(terrain_elevation / 31.0, 0.0, 1.0));
	return color * mix(1.0, brightness, clamp(coverage, 0.0, 1.0));
}
