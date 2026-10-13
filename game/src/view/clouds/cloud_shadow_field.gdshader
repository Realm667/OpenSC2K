shader_type canvas_item;
render_mode unshaded;
#include "res://src/view/clouds/cloud_field.gdshaderinc"
void fragment() {
	float cover = cloud_sample(UV * cloud_span, cloud_shadow_lod(), -1.0).a;
	COLOR = vec4(cover, cover, cover, 1.0);
}
