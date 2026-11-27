import Foundation

// 関数型スタイルで書くための小さな汎用ヘルパー。

extension Sequence {
    /// 先頭から順に、各要素を直前のグループに加えるか新しいグループを始めるかを `belongs` で決めて分割する。
    /// 例: `[1, 2, 4, 5].grouped { $1 - $0.last! == 1 }` → `[[1, 2], [4, 5]]`
    func grouped(while belongs: ([Element], Element) -> Bool) -> [[Element]] {
        reduce(into: []) { groups, element in
            if let last = groups.last, belongs(last, element) {
                groups[groups.count - 1].append(element)
            } else {
                groups.append([element])
            }
        }
    }

    /// 隣り合う 2 要素が `isContinuous` を満たす限り同じグループにまとめる。
    func chunked(by isContinuous: (Element, Element) -> Bool) -> [[Element]] {
        grouped { group, element in isContinuous(group[group.count - 1], element) }
    }
}

extension Sequence where Element: Hashable {
    /// 最初に現れた順を保ったまま重複を除く。
    func uniqued() -> [Element] {
        reduce(into: (seen: Set<Element>(), result: [Element]())) { acc, element in
            if acc.seen.insert(element).inserted { acc.result.append(element) }
        }.result
    }
}

extension Sequence where Element: AdditiveArithmetic {
    func sum() -> Element { reduce(.zero, +) }

    /// 累積和（prefix sum）。
    func cumulativeSums() -> [Element] {
        reduce(into: []) { sums, x in sums.append((sums.last ?? .zero) + x) }
    }
}

extension Result {
    var success: Success? { try? get() }

    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

/// 入力と結果の組から、成功したものだけを辞書にする。
func successes<Input, Key: Hashable, Value>(
    _ pairs: some Sequence<(Input, Result<Value, Error>)>,
    keyedBy key: (Input) -> Key
) -> [Key: Value] {
    Dictionary(uniqueKeysWithValues: pairs.compactMap { input, result in result.success.map { (key(input), $0) } })
}

/// 入力と結果の組から、失敗したものだけを辞書にする。
func failures<Input, Key: Hashable, Value>(
    _ pairs: some Sequence<(Input, Result<Value, Error>)>,
    keyedBy key: (Input) -> Key
) -> [Key: Error] {
    Dictionary(uniqueKeysWithValues: pairs.compactMap { input, result in result.failure.map { (key(input), $0) } })
}
