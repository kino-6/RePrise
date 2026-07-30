"""tasks.md の先頭に進み具合を書き込む。

    python tools/tasks_status.py

終わった項目は tasks.md から消して docs/tasks_archive.md へ移す運用なので、
tasks.md だけを見ると「ずっと [ ] のまま」に見えて、進んでいないように読める。
完了記録の行数と直近の 5 行を先頭に置いて、動いていることがファイル内で分かるようにする。

`docs/tasks_archive.md` は現状「1 タスク = 1 行」ではない。ここで数える `- ` は
完了タスク数ではなく、完了記録の箇条書き行数である。タスクIDから正しい件数を
出せるようになるまでは、完了件数とは呼ばない。

棚卸し（項目を控えへ移す）をしたら、これを回してヘッダを更新すること。
"""

import pathlib
import re

tasks = pathlib.Path("tasks.md")
archive = pathlib.Path("docs/tasks_archive.md")

archive_text = archive.read_bytes().decode("utf-8")
done = [
    ln.rstrip("\r") for ln in archive_text.split("\n")
    if ln.startswith("- ")
]
recent = done[-5:][::-1]

body = tasks.read_bytes().decode("utf-8")
# 既存のヘッダ（進み具合）だけを捨ててから付け直す。
# 完了Gateは進み具合と次の仕事の間にあるので、そこまで消さない。
body = re.sub(r"## 進み具合.*?(?=## 完了Gate|## 次にやる)", "", body, flags=re.S)
open_items = len(re.findall(r"^- \[ \]", body, flags=re.M))

header = f"""## 進み具合

**完了記録 {len(done)} 行（実タスク数は再集計待ち） / 残り {open_items} 件。**

終わった項目はここから消して `docs/tasks_archive.md` へ移すので、
このファイルに `[x]` は残らない。**動いているかどうかは下の「直近に済んだこと」で見る。**
理由まで読みたいときは控えのほうを開く。

### 直近に済んだこと

"""
for line in recent:
    header += line + "\n"
header += "\n"

body = body.replace("## 次にやる", header + "## 次にやる", 1)
# 改行を自動変換せず、そのまま戻す。このリポジトリには既存の CRLF があるため、
# text mode で全行を変換すると、ヘッダ更新だけで全ファイル差分になってしまう。
tasks.write_bytes(body.encode("utf-8"))
print("完了記録 %d 行 / 残 %d 件, tasks.md %d 行" % (
    len(done), open_items, len(body.split("\n"))
))
