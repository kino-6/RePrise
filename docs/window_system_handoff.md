# 汎用Windowシステム実装引き継ぎ

担当: Claude  
設計・棚卸し: Codex  
作成日: 2026-07-31

## 結論

新しい窓絵や `draw_window()` の描き直しは不要。
現在の問題は、各Viewが `Rect2`、行送り、列幅、表示件数を個別に計算し、
描画後の検査で初めて見切れに気付くことにある。

既存の `PixelUI` を描画エンジンとして残し、その上へ次の2層を追加する。

1. **`UiWindowFrame`** — 画面内の窓を登録し、画面外・窓同士の重なりを描画前に検査する。
2. **`UiWindow`** — 1枚の窓の内側を見出し・本文・一覧・フッターへ割り当て、
   文字、行、列、ページの収まりを描画前に決める。

一括置換はしない。新規クラスを単体テストした後、出店1画面を試験移行し、
結果を見てから残りへ広げる。

## 現状の棚卸し

既に使えるもの:

- `src/ui/pixel_ui.gd`
  - `draw_window()` — SFC後期調の9-slice枠、階調、面取り、影
  - `content()` — 枠の内側
  - `draw_text()` / `draw_text_right()`
  - `wrap()` / `clip()`
  - `--ui-check` 時の文字見切れ・同一行の重なり検出
- `src/ui/menu_list.gd`
  - 選択位置を中央付近に保つページ範囲
  - カーソルと現在位置の表示
- `src/ui/notice.gd`
  - 通知の寿命管理
- `tools/check_ui.py`
  - 23画面を撮影し、`PixelUI.ui_violations()` をGateにする

明示的な `PixelUI.draw_window()` は8ファイル25か所にある。

| View | 窓数 | 主な危険 |
| --- | ---: | --- |
| `stronghold_view.gd` | 4 | 職業数、熟練段階、名簿人数で行・列が増える |
| `field_menu.gd` | 4 | 状態ごとに本文構造が変わり、見えない選択肢が発生しやすい |
| `shop_view.gd` | 4 | 品名・能力差・説明文・所持金を同時に置く |
| `battle_view.gd` | 4 | コマンド、技、道具、ログで状態と表示件数が変わる |
| `event_view.gd` | 3 | AI由来の可変長文と選択肢 |
| `settings_view.gd` | 2 | キー名の長さが環境で変わる |
| `explore_hud.gd` | 2 | 常時表示のためマップ上の物を隠しやすい |
| `result_screen.gd` | 2 | 戦記と習得技の可変長文 |

現在の検査には次の穴がある。

- 文字の開始点がどの窓にも入っていない場合、窓外の文字として検査対象外になる。
- 文字以外のカーソル、アイコン、ゲージ、窓同士の重なりは検出しない。
- 固定座標で描いた後に違反を見つけるため、レイアウトを直す判断は各Viewへ残る。
- 一覧の行数計算とフッター予約が画面ごとに異なる。
- `clip()` は情報を失っても描画自体は成功する。
- 撮影用状態に無い極端な名前、最大所持数、最大習得数はGateを通らない。

## 目的

- 選べる項目が画面外へ消える状態を作れない。
- 文章は自動折り返し、一覧は自動ページ化する。
- 省略は明示的に許可した場所だけで起こる。
- 漢字を収めるために14px未満へ縮小しない。
- 外枠、内側余白、行送り、ページ表示を全画面で同じ規約にする。
- 新しい職業、装備、イベントを増やしても、内容追加だけで既存画面が壊れない。
- 同じ入力から同じ配置になる。乱数、時刻、フレーム時間はレイアウトに使わない。

## 非目標

- Godotの `Control` ノード群への全面移行
- 解像度512x320やSFCアート方針の変更
- `window.png` や生成器の変更
- 入力状態機械、ゲームロジック、セーブ形式の共通化
- すべてのViewを一度に書き換えること
- 文字を自動縮小して無理に収めること

## 配置するファイル

最初の実装単位:

```text
src/ui/window_frame.gd       class_name UiWindowFrame
src/ui/ui_window.gd          class_name UiWindow
tests/test_window_system.gd  単独実行できるレイアウトテスト
```

必要になった場合だけ:

```text
src/ui/window_slot.gd
```

最初からクラスを細分化しない。辞書だけで巨大な仕様を渡す方式にもせず、
IDE補完と型検査が効く小さなクラスにする。

## API契約

以下は呼び出し側から見た契約。名前の微調整は可能だが、責務は変えない。

```gdscript
var frame := UiWindowFrame.new(Rect2(Vector2.ZERO, PixelUI.SCREEN))
var body := frame.add_window(&"shop.body", BODY_RECT)

var title := body.take_top(&"title", 24.0)
var footer := body.take_bottom(&"footer", 20.0)
var page := body.take_list(
    &"items", item_ids.size(), _index, 22.0
)

frame.validate()
frame.draw_windows(self, WINDOW_TEX)

body.draw_text(self, title, Terms.SHOP, PixelUI.SIZE_HEAD)
for row in page.rows:
    body.draw_text(self, row.rect, item_name(row.index))
body.draw_text(self, footer, operation_hint())
```

### `UiWindowFrame`

保持するもの:

- 基準画面矩形。通常は `Rect2(Vector2.ZERO, PixelUI.SCREEN)`
- 登録された窓IDと外側矩形
- 意図的な重なりの指定
- 検出した違反

必要な操作:

- `add_window(id, rect, options = {}) -> UiWindow`
- `validate() -> bool`
- `draw_windows(canvas, texture)`
- `violations() -> Array[String]`

規約:

- IDは1フレーム内で一意。
- 外枠は画面内へ完全に収める。標準安全余白は8px。
- 窓同士は標準で重ねない。
- モーダル、通知、戦闘サブウィンドウの重なりは
  `{"overlay": true, "layer": N}` のように明示する。
- 違反を勝手に補正して隠さない。開発時は違反として報告する。
- `PixelUI.ui_violations()` と同じ出力へ統合し、既存の `check_ui.py` が拾えること。

### `UiWindow`

保持するもの:

- 外枠と `PixelUI.content()` で得た内側矩形
- 上から使うカーソルと下から使うカーソル
- 予約済みスロット
- 一覧の表示範囲
- 省略、折り返し、ページ化の記録

必要な操作:

- `take_top(id, height) -> Rect2`
- `take_bottom(id, height) -> Rect2`
- `take_block(id, height) -> Rect2`
- `take_list(id, total, selected, row_height, options = {}) -> Dictionary`
- `split_columns(slot, widths, gap = 8.0) -> Array[Rect2]`
- `draw_text(canvas, slot, text, size, color, overflow)`
- `draw_paragraph(canvas, slot, text, size, line_height)`
- `slot_rect(id) -> Rect2` — ゲージやアイコン等の独自描画用
- `validate() -> bool`

`take_list()` は最低限、次を返す。

```gdscript
{
    "first": int,
    "last": int,          # 終端の次
    "rows": Array,        # {index, rect}
    "page_text": String,  # 例: 3/15。全件表示なら空
}
```

ページ範囲の計算は既存の `MenuList.range_of()` を使う。
同じ数式を新クラスへ書き写さない。

## はみ出し時の方針

既定値は `ERROR`。黙って切らない。

| 種類 | 方針 |
| --- | --- |
| 見出し、コマンド、報酬名 | `ERROR`。必要なら窓か列を設計し直す |
| 説明文、戦記、イベント文 | `WRAP`。高さ不足なら文章ページを分ける |
| 道具・職業・装備一覧 | `PAGINATE`。選択中の行を必ず表示する |
| 一覧の補助説明 | `ELLIPSIS`可。ただし別の詳細窓で全文を読めること |
| 通知 | 画面幅まで拡張し、超えたら最大2行へ折り返して高さも増やす |
| 漢字を含む文 | 14px以上。縮小による解決は禁止 |

列幅は「名前150px」のようなView固有の勘で決めず、
固定列（個数、MP、価格）を先に引き、残りを名前・説明の可変列へ渡す。

```text
内側幅
├─ 名前: flex
├─ gap: 8
├─ 個数: 右寄せ 36
├─ gap: 8
└─ 価格: 右寄せ 64
```

固定列の値が収まらない場合も、隣の列へ食い込ませず違反にする。

## 独自描画との境界

汎用化するのは配置であり、画面固有の意味ではない。

- HPゲージ、敵画像、職業立ち絵は従来どおり各Viewが描く。
- ただし座標は `slot_rect()` で予約した矩形から取る。
- カーソルは行スロットを `MenuList.draw_cursor()` へ渡す。
- Viewが `UiWindow.content_rect.position + Vector2(232, 30)` のような
  新しいマジックナンバーを足し始めたら移行失敗とする。
- 例外的な重ね描きは `overlay` スロットとして名前を付ける。

## 導入順

### G-1: 基盤だけを作る

- 新規2クラスと `tests/test_window_system.gd` を追加。
- 本番Viewは変更しない。
- `PixelUI` には既存違反一覧へ追加する小さな公開窓口だけ足してよい。
- `main.gd`、`tests/test_core.gd`、ゲームロジックには触れない。

### G-2: 出店を試験移行する

`shop_view.gd` の4窓だけを移行する。

選定理由:

- 見出し、一覧、詳細、操作メニューが揃っている。
- 戦闘のような時間依存演出が無い。
- 品名、説明、能力差、価格という長さの違うデータを検証できる。

同時に `PixelUI.draw_notice()` を新しい通知レイアウトへ通し、
長い装備名＋ゴールドの通知が画面外へ出ないようにする。

### G-3: 残りを小さい順に移行する

1. `settings_view.gd`
2. `result_screen.gd`
3. `explore_hud.gd`
4. `event_view.gd`
5. `stronghold_view.gd`
6. `field_menu.gd`
7. `battle_view.gd`

戦闘は最後。開閉アニメーション、メッセージ、コマンド、対象選択が同じ窓を
時間で使い分けるため、基盤が安定する前に触らない。

各Viewを1つ移行するたびに検査し、複数Viewをまとめて直して原因を混ぜない。

## 競合を避ける作業境界

- この文書作成時点ではゲームコードを実装していない。
- Claudeは最初に `git status --short` を読み、他者の変更を戻さない。
- **G-1では新規ファイルを中心にし、`main.gd` と `tests/test_core.gd` を編集しない。**
- 本番Viewの変更はG-2の `shop_view.gd` 1本から始める。
- `assets/` は生成物なので触らない。
- `PixelUI.draw_window()`、`MenuList`、`Notice` を削除しない。
- 既存View用APIは全移行まで残す。途中状態でもゲームが起動すること。
- 無関係な整形、改行コード変更、名称変更を同じ差分へ混ぜない。
- G-1、G-2、G-3を別コミットにできる粒度で作る。

## Gate

### G-1 単体Gate

実行:

```powershell
godot --headless --script res://tests/test_window_system.gd
```

最低限のfixture:

1. 画面外へ1px出した窓を失敗にする。
2. 標準窓を1px重ねて失敗にする。
3. `overlay` 指定した窓の重なりだけ許可する。
4. 同じ窓IDを2回使うと失敗する。
5. 上予約と下予約が交差すると失敗する。
6. 一覧0件、1件、表示上限ちょうど、上限+1、100件を検査する。
7. どの選択位置でも選択中の行が表示範囲内にある。
8. 長い日本語を折り返して文字を1字も失わない。
9. `ERROR` の長文は失敗し、明示した `ELLIPSIS` だけ省略できる。
10. 漢字を12pxで描こうとした場合は失敗する。
11. 同じ入力から全スロット矩形とページ範囲が一致する。

### G-2 試験移行Gate

```powershell
godot --headless --script res://tests/test_window_system.gd
godot --headless --script res://tests/test_core.gd
python tools/check_ui.py
godot --path . --accessibility disabled -- --shot=shop --ui-check
```

追加fixture:

- 最長の道具名、装備名、説明文
- 所持数3桁、価格4桁、ゴールド最大桁
- 品目0件、1件、表示上限、表示上限+1、30件
- 通知が1行に収まる場合と2行になる場合
- 選択中の品の全文が詳細窓で読める

画像は `docs/preview/screen_shop.png` を目視する。
検査0件だけで完了にしない。

### G-3 全移行Gate

```powershell
godot --headless --script res://tests/test_window_system.gd
godot --headless --script res://tests/test_core.gd
python tools/check_ui.py
```

次の代表画面を目視する。

```text
stronghold / job / upgrade / party
shop / event
commands / items / battle
menu / status / equip / jobmenu
settings / result / win
```

完了条件:

- 明示的な `PixelUI.draw_window()` が移行対象Viewに残っていない。
- View内の行数に応じた `if at.y > ...` が残っていない。
- 選べるが見えない項目が0件。
- 意図しない省略が0件。
- `check_ui.py` が正常23画面で成功し、違反fixtureで終了コード1。
- D-5の漢字サイズGateとも矛盾しない。

## 禁止する近道

- フォントを小さくして収める。
- `clip()` を全ラベルへ一律適用する。
- 最後の数件を描かない。
- ウィンドウ外へ説明を逃がす。
- `--ui-check` 中だけ別の配置にする。
- 画面ごとに新しいページ計算を書く。
- `Control` ノードへ一括移植する。
- 見切れを直すためにゲーム内データの名称や説明を短くする。

## Claudeへそのまま渡す指示

> `AGENTS.md` と `docs/window_system_handoff.md` を読んでください。
> まずG-1だけを実装し、G-2以降へ進まないでください。
> `UiWindowFrame`、`UiWindow`、単独の `test_window_system.gd` を追加し、
> 本番View、`main.gd`、`tests/test_core.gd`、`assets/` は変更しないでください。
> 既存の `PixelUI`、`MenuList`、`Notice` を再利用し、描画方式を置き換えないでください。
> 正常fixtureだけでなく、画面外、窓重複、予約交差、長文、一覧上限+1が
> 確実に失敗するfixtureまで通してください。作業前後の `git status --short` を比較し、
> 無関係な変更を戻したり整形したりしないでください。
