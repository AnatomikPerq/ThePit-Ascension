shader_type canvas_item;

// The railgun charge indicator: ONE drawing of the gun, lit progressively.
//
// The obvious way to show six charges is six drawings. This is not that, and the
// reason is the ult that is coming: its meter drains continuously the whole time
// it is up, and faster while the trigger is held, and no number of frames is a
// continuous value. So the whole state of this widget is a single float.
//
//   fill = 0.0   nothing. Every energy cell is a dead slot.
//   fill = n/6   n charges in the gun.
//   fill = 1.0   full.
//
// A charge landing, an ult draining and a shot being spent are all the same
// uniform moving. Nothing about the art has to know which.
//
// ## The mask
//
// `order_mask` is a second drawing the same size as the first, in greys. Black
// means "this pixel is not energy — draw it exactly as painted", which is the
// whole body of the gun. Anything else means "this is an energy cell, and this
// value IS ITS PLACE IN THE FILL ORDER": 1 lights first, 255 lights last.
//
// That is what decouples the fill order from the drawing. It is generated as a
// left-to-right ramp by tools/aseprite/build_rail_mask.lua and then it is just a
// picture — repaint it in Aseprite to light the receiver before the barrel, or
// to group the cells into six blocks that each light as one, and nothing in code
// changes.
//
// ## The drained look
//
// By default a cell that is not lit is the same pixel pushed down to `drained`,
// keeping its own brightness so the shading inside the cells survives. If you
// would rather draw what an empty slot looks like — hollow, unlit, whatever the
// gun is actually made of under the glow — put that drawing in `drained_tex` and
// set `use_drained_tex`. The two are the same shader; only the .tres changes.

uniform sampler2D order_mask : hint_default_black, filter_nearest;

// The one value. 0 is empty, 1 is full.
uniform float fill : hint_range(0.0, 1.0) = 0.0;

// What an unlit cell fades to. Kept a green rather than a grey so a spent gun
// still reads as a gun full of empty energy slots.
uniform vec4 drained : source_color = vec4(0.14, 0.22, 0.16, 1.0);

// The travelling bright edge at the fill front. Without it the meter changes
// value without ever looking like it is FILLING — this is the part that reads as
// energy flowing in rather than as a bar being resized.
uniform float front_width : hint_range(0.0, 0.5) = 0.07;
uniform float front_glow : hint_range(0.0, 1.0) = 0.9;

// Driven by an AnimationPlayer clip, not by TIME: one pulse when a charge lands,
// which is how six discrete charges stay readable on a continuous bar. An ult
// can hold it up to make a draining meter look alive.
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D drained_tex : hint_default_transparent, filter_nearest;
uniform bool use_drained_tex = false;

// The bloom around the lit cells. It is what makes the meter readable from the
// corner of the eye at a glance: the cells themselves are a few pixels of the
// drawing, and without something bleeding out of them the whole widget reads as
// a picture of a gun rather than as a gauge.
//
// Nothing here blurs the IMAGE — it re-samples the ORDER MASK in a ring and asks
// how much of the neighbourhood is lit, which is cheaper and, more usefully,
// glows in the energy colour rather than in whatever the drawing happens to be.
uniform vec4 energy : source_color = vec4(0.76, 1.0, 0.24, 1.0);
uniform float glow : hint_range(0.0, 3.0) = 1.1;
// In TEXELS of the mask, not in UV: the drawing is 158×42, so a radius in UV
// would be four times wider than it is tall.
uniform float glow_radius : hint_range(0.0, 12.0) = 3.5;

const vec2 RING[8] = {
	vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
	vec2(0.7, 0.7), vec2(-0.7, 0.7), vec2(0.7, -0.7), vec2(-0.7, -0.7)
};


// The mask is DATA, and Godot hands it back as COLOUR.
//
// A 2D texture is sampled through an sRGB decode, so a cell painted 128 comes
// back as ~0.216 rather than 0.5 — every order value is pulled down, so far more
// of them fall under `fill` than should. Measured, before this was here: at
// fill = 1/6 a third of the gun was lit instead of a sixth, and by fill = 5/6 it
// was already saturated, so the top of the scale did nothing at all.
//
// Undoing the decode puts the mask back in the units it was painted in, which is
// what lets `tools/aseprite/build_rail_mask.lua` write a plain linear ramp and
// lets the file be edited by hand and mean what it looks like.
float order_at(vec2 uv) {
	float m = texture(order_mask, clamp(uv, vec2(0.0), vec2(1.0))).r;
	return m;
}


float lit_at(vec2 uv) {
	float m = order_at(uv);
	return (m > 0.0 && m <= fill) ? 1.0 : 0.0;
}

// Nested rather than early-returned: Godot's shader language rejects `return`
// inside fragment(), and `order == 0.0` — the whole body of the gun — is by far
// the most common case, so it is the branch that does nothing.
void fragment() {
	float order = order_at(UV);
	if (order > 0.0) {
		if (order <= fill) {
			float behind_front = fill - order;
			float edge = 1.0 - smoothstep(0.0, front_width, behind_front);
			COLOR.rgb = mix(COLOR.rgb, vec3(1.0), edge * front_glow);
			COLOR.rgb *= 1.0 + pulse * 0.4;
		} else if (use_drained_tex) {
			COLOR.rgb = texture(drained_tex, UV).rgb;
		} else {
			// Its own brightness, in the dead colour — so a cell that was shaded
			// stays shaded instead of flattening to one block of dark green.
			float lum = dot(COLOR.rgb, vec3(0.3, 0.5, 0.2));
			COLOR.rgb = drained.rgb * lum * 2.2;
		}
	}

	// The bloom, over everything — including the transparent gaps in and around
	// the drawing, which is where most of it is actually seen. Two rings, the
	// outer one at half weight, for a falloff rather than a hard corona.
	if (glow > 0.0) {
		vec2 texel = 1.0 / vec2(textureSize(order_mask, 0));
		float near_lit = 0.0;
		for (int i = 0; i < 8; i++) {
			near_lit += lit_at(UV + RING[i] * glow_radius * texel);
			near_lit += 0.5 * lit_at(UV + RING[i] * glow_radius * 2.0 * texel);
		}
		float halo = clamp(near_lit / 12.0, 0.0, 1.0) * glow * (1.0 + pulse * 0.5);
		COLOR.rgb += energy.rgb * halo * 0.55;
		COLOR.a = clamp(COLOR.a + halo * 0.42, 0.0, 1.0);
	}
}
