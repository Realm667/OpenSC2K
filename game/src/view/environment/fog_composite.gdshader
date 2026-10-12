shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
uniform sampler2D fog_surface : filter_linear, repeat_disable;
void fragment() { COLOR = texture(fog_surface, UV); }
