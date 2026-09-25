shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec3 deep_color : source_color = vec3(0.025, 0.10, 0.08);
uniform vec3 light_color : source_color = vec3(0.065, 0.21, 0.14);
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(world_position.x * 3.3 + TIME * 0.7) * cos(world_position.z * 2.4 - TIME * 0.45);
	VERTEX.y += wave * 0.008;
}

void fragment() {
	float ripple = sin(world_position.x * 5.0 + world_position.z * 1.7 + TIME * 0.8);
	float crossing = cos(world_position.z * 4.1 - world_position.x * 1.8 - TIME * 0.55);
	NORMAL = normalize(NORMAL + vec3(ripple * 0.055, 0.0, crossing * 0.055));
	ALBEDO = mix(deep_color, light_color, 0.25 + 0.12 * ripple * crossing);
	ROUGHNESS = 0.19;
	METALLIC = 0.12;
	SPECULAR = 0.7;
	ALPHA = 0.90;
}
