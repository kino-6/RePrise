extends RefCounted

## 破壊的な選択の段階だけを扱う純粋関数。
##
## View から分けることで、音や入力に依存せず「何回の明示確認で実行へ届くか」を
## headless テストから守れる。1=最初 / 2=最終 / 3=実行、0=閉じる。


static func next_run_abandon_stage(stage: int, confirmed: bool) -> int:
	if stage not in [1, 2] or not confirmed:
		return 0
	return stage + 1
