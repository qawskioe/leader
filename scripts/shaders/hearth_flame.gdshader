shader_type spatial;
render_mode unshaded, cull_disabled;
varying float flame_height;

void vertex() {
	flame_height = VERTEX.y;
	VERTEX.x += sin(TIME * 5.0 + VERTEX.y * 11.0) * 0.035 * max(VERTEX.y - 0.15, 0.0);
	VERTEX.z += cos(TIME * 4.0 + VERTEX.y * 9.0) * 0.025 * max(VERTEX.y - 0.15, 0.0);
}

void fragment() {
	float t = clamp((flame_height - 0.15) / 0.8, 0.0, 1.0);
	ALBEDO = mix(vec3(1.0, 0.76, 0.18), vec3(0.95, 0.12, 0.015), t);
}
