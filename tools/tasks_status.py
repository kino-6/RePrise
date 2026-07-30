"""tasks.md の先頭に進み具合を書き込む。

    python tools/tasks_status.py

終わった項目は tasks.md から消して docs/tasks_archive.md へ移す運用なので、
tasks.md だけを見ると「ずっと [ ] のまま」に見えて、進んでいないように読める。
済んだ件数と直近の 5 件を先頭に置いて、動いていることがファイル内で分かるようにする。

棚卸し（項目を控えへ移す）をしたら、これを回してヘッダを更新すること。
"""

import pathlib
import re

tasks = pathlib.Path("tasks.md")
archive = pathlib.Path("docs/tasks_archive.md")

archive_text = archive.read_text(encoding="utf-8")
done = [ln for ln in archive_text.split("\n") if ln.startswith("- ")]
recent = done[-5:][::-1]

body = tasks.read_text(encoding="utf-8")
# 既存のヘッダ（進み具合）を捨ててから付け直す
body = re.sub(r"## 進み具合.*?(?=## 次にやる)", "", body, flags=re.S)
open_items = len(re.findall(r"^- \[ \]", body, flags=re.M))

header = f"""## 進み具合

**済んだこと {len(done)} 件 / 残り {open_items} 件。**

終わった項目はここから消して `docs/tasks_archive.md` へ移すので、
このファイルに `[x]` は残らない。**動いているかどうかは下の「直近に済んだこと」で見る。**
理由まで読みたいときは控えのほうを開く。

### 直近に済んだこと

"""
for line in recent:
    header += line + "\n"
header += "\n"

body = body.replace("## 次にやる", header + "## 次にやる", 1)
tasks.write_text(body, encoding="utf-8")
print("済 %d / 残 %d, tasks.md %d 行" % (len(done), open_items, len(body.split("\n"))))
