shader_type canvas_item;

// 画面を角ブロックへ粗くする（SFC のモザイク、$2106 相当）。
//
// 設計は docs/screen_transition_design.md。守ること:
//
//   * 粒は**ゲーム画素**（既定 512x320）で切る。ウィンドウ画素で切ると
//     表示倍率によって粒の大きさが変わり、2 倍と 3 倍で別物になる。
//   * `block` は整数段（1..16）で渡す。実機に 3.7 画素の粒は無い。
//   * 明るさは**下げる方向にだけ**使う。SFC の明度レジスタは既定が最大なので、
//     白く飛ばすことはできなかった。

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;

/// 画面の論理解像度。
uniform vec2 screen_size = vec2(512.0, 320.0);

/// 粒の大きさ（1 = 素のまま、16 = 実機の最大）。
uniform float block : hint_range(1.0, 16.0) = 1.0;

/// 明るさ。16 段に量子化した値を渡す（0 = 黒、1 = 素のまま）。
uniform float brightness : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 game_px = SCREEN_UV * screen_size;
	// 粒の**中心**を拾う。左上を拾うと 1 画素ぶん左上へずれて見える。
	vec2 snapped = (floor(game_px / block) + 0.5) * block;
	vec3 c = texture(screen_tex, snapped / screen_size).rgb;
	COLOR = vec4(c * brightness, 1.0);
}
