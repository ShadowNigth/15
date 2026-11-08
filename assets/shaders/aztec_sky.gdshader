shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// Continuous world-direction storm clouds; retain original storm artwork at horizon.
uniform sampler2D original_sky : source_color, filter_linear, repeat_disable;
varying vec3 sky_direction;
float hash3(vec3 p) {
 p=fract(p*.1031); p+=dot(p,p.yzx+33.33); return fract((p.x+p.y)*p.z);
}
float noise3(vec3 p) {
 vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() {
 sky_direction=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz-CAMERA_POSITION_WORLD;
}
void fragment() {
 vec3 d=normalize(sky_direction);
 vec3 original=texture(original_sky,UV).rgb;
 vec3 p=d*vec3(4.0,9.0,4.0)+vec3(TIME*.0015,2.0,TIME*.001);
 float cloud=noise3(p)*.60+noise3(p*2.03)*.28+noise3(p*4.07)*.12;
 vec3 storm=mix(vec3(.14,.20,.23),vec3(.51,.59,.58),smoothstep(.25,.74,cloud));
 float opening=pow(max(dot(d,normalize(vec3(-.38,.82,.42))),0.0),16.0);
 storm+=vec3(.09,.10,.075)*opening;
 ALBEDO=mix(original,storm,smoothstep(.03,.35,d.y)*.72);
}
