class_name DetRng
extends RefCounted

## 決定的疑似乱数生成器。
##
## ローグライクの生命線は「同じシードなら必ず同じ結果」であること。リプレイ、
## 不具合の再現、バランス調整の自動シミュレーションが全部ここに乗る。
## Godot の RandomNumberGenerator はバージョン間で実装が変わりうるので使わない。
##
## アルゴリズムは xoshiro128**。全演算を 32bit にマスクしてあるため
## int64 の桁あふれが起きず、どのプラットフォームでも同じ数列を返す。

const MASK := 0xFFFFFFFF

var _s0: int
var _s1: int
var _s2: int
var _s3: int


func _init(seed_value: int = 0) -> void:
	seed_with(seed_value)


func seed_with(seed_value: int) -> void:
	# SplitMix32 で 1 個の種を 4 個の状態語へ広げる。状態が全部 0 だと
	# xoshiro は永久に 0 を返すので、その場合だけ定数を入れて回避する。
	var z := seed_value & MASK
	_s0 = _splitmix32(z)
	z = (z + 0x9E3779B9) & MASK
	_s1 = _splitmix32(z)
	z = (z + 0x9E3779B9) & MASK
	_s2 = _splitmix32(z)
	z = (z + 0x9E3779B9) & MASK
	_s3 = _splitmix32(z)
	if _s0 == 0 and _s1 == 0 and _s2 == 0 and _s3 == 0:
		_s0 = 0x9E3779B9


func _splitmix32(x: int) -> int:
	var z := (x + 0x9E3779B9) & MASK
	z = ((z ^ (z >> 16)) * 0x21F0AAAD) & MASK
	z = ((z ^ (z >> 15)) * 0x735A2D97) & MASK
	return (z ^ (z >> 15)) & MASK


func _rotl(x: int, k: int) -> int:
	return ((x << k) | (x >> (32 - k))) & MASK


## 次の 32bit 値。0 <= 戻り値 <= 0xFFFFFFFF
func next_u32() -> int:
	var result := (_rotl((_s1 * 5) & MASK, 7) * 9) & MASK
	var t := (_s1 << 9) & MASK
	_s2 ^= _s0
	_s3 ^= _s1
	_s1 ^= _s2
	_s0 ^= _s3
	_s2 ^= t
	_s3 = _rotl(_s3, 11)
	return result


## lo 以上 hi 以下の整数。lo > hi なら lo を返す。
func range_i(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + next_u32() % (hi - lo + 1)


## percent% の確率で true。
func chance(percent: int) -> bool:
	return range_i(1, 100) <= percent


func pick(items: Array):
	if items.is_empty():
		return null
	return items[next_u32() % items.size()]


## Fisher-Yates。配列を破壊的に混ぜる。
func shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := int(next_u32() % (i + 1))
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp


## 用途ごとに独立した子 RNG を切り出す。
##
## 「地形生成で乱数を 1 個多く引いたら宝箱の中身まで全部変わった」という事故を
## 防ぐための仕組み。系統ごとに fork しておけば、片方をいじっても他方は動かない。
func fork(label: String) -> DetRng:
	var h := 0
	for i in label.length():
		h = ((h * 31) + label.unicode_at(i)) & MASK
	return DetRng.new((next_u32() ^ h) & MASK)
