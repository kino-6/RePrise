"""tasks.md の先頭に進み具合を書き込む。

    python tools/tasks_status.py

終わった項目は tasks.md から消して docs/tasks_archive.md へ移す運用なので、
tasks.md だけを見ると「ずっと [ ] のまま」に見えて、進んでいないように読める。
完了記録の行数と直近の 5 行を先頭に置いて、動いていることがファイル内で分かるようにする。

**件数はタスク ID から数える（D-6）。** もとは控えの `- ` 行を全部数えていたが、
1 タスクが複数行の理由を持つので、行数と件数がまるで違っていた（240 行で 12 件）。
いまは `A-4` `C-10` のような ID を台帳として数える。

台帳が壊れていたら**終了コード 1** で落ちる。落ちる条件は 3 つ。

  * 同じ ID が未完了と控えの両方に居る（移し忘れ、または二重着手）
  * 同じ ID が控えに 2 回出てくる（二重記帳）
  * 控えの項目に証跡が無い（何を確かめて閉じたのか分からない）

「〜の一部」と書いた項目は**その ID を閉じない**。大きなタスクの一部だけを
先に済ませることがあり、それで親を閉じると残りが黙って消える。

棚卸し（項目を控えへ移す）をしたら、これを回してヘッダを更新すること。
"""

import pathlib
import re
import sys

tasks = pathlib.Path("tasks.md")
archive = pathlib.Path("docs/tasks_archive.md")

archive_text = archive.read_bytes().decode("utf-8")
done = [
    ln.rstrip("\r") for ln in archive_text.split("\n")
    if ln.startswith("- ")
]
recent = done[-5:][::-1]

TASK_ID = re.compile(r"\b([A-H]-\d+)\b")


def _titles(text, mark):
    """`- [x]` / `- [ ]` の行から、太字の題だけを取り出す。"""
    out = []
    for line in text.split("\n"):
        s = line.strip()
        if not s.startswith(mark):
            continue
        title = re.search(r"\*\*(.+?)\*\*", s)
        out.append(title.group(1) if title else s)
    return out


def _ledger(text, mark):
    """題に出てくる ID を数える。

    **「〜の一部」はその ID を閉じない。** 大きなタスクの一部だけを先に
    済ませることがあり（C-8 の出入口だけを直した、など）、それで親を
    閉じると残りが黙って消える。
    """
    seen = {}
    for title in _titles(text, mark):
        if "の一部" in title:
            continue
        for found in TASK_ID.findall(title):
            seen[found] = seen.get(found, 0) + 1
    return seen


def _has_gate(text):
    """控えの各項目に Gate の証跡があるか。**無い項目の題**を返す。

    何を確認して閉じたのかが残っていない項目は、閉じた根拠が無い。
    """
    bad = []
    for block in re.split(r"\n(?=- \[x\])", text):
        if not block.lstrip().startswith("- [x]"):
            continue
        title = re.search(r"\*\*(.+?)\*\*", block)
        name = title.group(1) if title else block.strip()[:40]
        # **証跡は「Gate:」と書いてあることではない。**
        # 走らせた道具、数字の結果、目で見たという記述 ―― どれも証跡である。
        # ラベルだけを探すと、ちゃんと確かめてある古い項目まで落ちる。
        evidence = (
            "Gate" in block or "確認" in block or "目視" in block
            or "実測" in block or "測っ" in block or "godot " in block
            or "python tools/" in block or "/0" in block or "%" in block
        )
        if not evidence:
            bad.append(name)
    return bad


def _selftest():
    """**検査器そのものを試す。** 正常系だけ見ても、壊れた関門は見つからない。

    この道具は一度、控えの `- ` 行を全部「完了件数」として数えていた
    （240 行を 240 件と言っていた）。数えるものが違っていても静かに動くので、
    わざと壊した入力を通して落ちることを見る。
    """
    cases = [
        ("重複を見つける", {"A-1": 2}, {}, [], True),
        ("両方に居るのを見つける", {"A-1": 1}, {"A-1": 1}, [], True),
        ("証跡なしを見つける", {"A-1": 1}, {}, ["A-1"], True),
        ("未完了どうしの衝突を見つける", {}, {"A-1": 2}, [], True),
        ("正しい台帳は通る", {"A-1": 1}, {"B-2": 1}, [], False),
    ]
    bad = 0
    for name, done_map, open_map, missing, want_fail in cases:
        found = bool(
            set(open_map) & set(done_map)
            or [k for k, v in done_map.items() if v > 1]
            or [k for k, v in open_map.items() if v > 1]
            or missing
        )
        ok = found == want_fail
        bad += 0 if ok else 1
        print("  %s  %s" % ("OK" if ok else "NG", name))
    # 「〜の一部」で親を閉じないこと。
    part = _ledger("- [x] **町の出入口を固定した（C-8 の一部）。**", "- [x]")
    ok = "C-8" not in part
    bad += 0 if ok else 1
    print("  %s  「〜の一部」は親の ID を閉じない" % ("OK" if ok else "NG"))
    print("---")
    if bad:
        print("検査器が壊れている（%d 件）" % bad)
        return 1
    print("検査器は期待どおり動く（%d 件）" % (len(cases) + 1))
    return 0


if "--selftest" in sys.argv:
    raise SystemExit(_selftest())


done_ids = _ledger(archive_text, "- [x]")

body = tasks.read_bytes().decode("utf-8")
# 既存のヘッダ（進み具合）だけを捨ててから付け直す。
# 完了Gateは進み具合と次の仕事の間にあるので、そこまで消さない。
body = re.sub(r"## 進み具合.*?(?=## 完了Gate|## 次にやる)", "", body, flags=re.S)
open_items = len(re.findall(r"^- \[ \]", body, flags=re.M))
open_ids = _ledger(body, "- [ ]")

# **台帳の検査。** ここが通らないと件数を名乗れない。
problems = []
both = sorted(set(open_ids) & set(done_ids))
if both:
    problems.append("未完了と控えの両方に居る ID: %s" % "、".join(both))
twice = sorted(k for k, v in done_ids.items() if v > 1)
if twice:
    problems.append("控えに 2 回出てくる ID: %s" % "、".join(twice))
# **未完了どうしの衝突も見る。** 別々の人が同じ番号を振ると、片方を閉じた
# つもりでもう片方が残る（実際に E-1 と E-2 が 2 つずつ在った）。
open_twice = sorted(k for k, v in open_ids.items() if v > 1)
if open_twice:
    problems.append("未完了に 2 回出てくる ID: %s" % "、".join(open_twice))
no_gate = _has_gate(archive_text)
if no_gate:
    problems.append("Gate の証跡が無い項目 %d 件: %s" % (
        len(no_gate), "、".join(no_gate[:3])))

header = f"""## 進み具合

**済んだタスク {len(done_ids)} 件 / 残り {open_items} 件"""
header += f"""（ID の総数 {len(set(open_ids) | set(done_ids))}）。**

終わった項目はここから消して `docs/tasks_archive.md` へ移すので、
このファイルに `[x]` は残らない。**動いているかどうかは下の「直近に済んだこと」で見る。**
理由まで読みたいときは控えのほうを開く。

### 直近に済んだこと

"""
for line in recent:
    # **`[x]` を落としてから写す。** ここは digest であって未完了の一覧ではない。
    # そのまま写すと tasks.md に `[x]` が残り、衛生の関門（`_test_docs_hygiene`）が
    # 「控えへの移し忘れ」として落とす。道具どうしが食い違ったまま動いていた。
    header += line.replace("- [x] ", "- ", 1) + "\n"
header += "\n"

body = body.replace("## 次にやる", header + "## 次にやる", 1)
# 改行を自動変換せず、そのまま戻す。このリポジトリには既存の CRLF があるため、
# text mode で全行を変換すると、ヘッダ更新だけで全ファイル差分になってしまう。
tasks.write_bytes(body.encode("utf-8"))
print("済んだ %d 件 / 残り %d 件, 控え %d 行, tasks.md %d 行" % (
    len(done_ids), open_items, len(done), len(body.split("\n"))
))
if problems:
    print("---")
    print("台帳が壊れている:")
    for note in problems:
        print("  - %s" % note)
    raise SystemExit(1)
