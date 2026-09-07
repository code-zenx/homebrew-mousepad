import Foundation

/// UTF-16 offsets where lines start. Rebuilt after every edit in one chunked pass over the
/// storage (C-speed copies, no per-character bridging), so the gutter, status bar and
/// Go to Line answer in O(log n) instead of rescanning the whole text each time.
public final class LineIndex {
    public private(set) var starts: [Int] = [0]

    public init() {}

    public var count: Int { starts.count }

    // ponytail: full rebuild per edit, ~10 ms for 20 MB. Splice by the edited range if that ever lags.
    public func rebuild(_ ns: NSString) {
        let n = ns.length
        var s = [0]
        s.reserveCapacity(starts.count)
        var buf = [unichar](repeating: 0, count: 65_536)
        var i = 0
        var afterCR = false
        while i < n {
            let len = min(buf.count, n - i)
            ns.getCharacters(&buf, range: NSRange(location: i, length: len))
            for k in 0..<len {
                let c = buf[k]
                if afterCR {
                    afterCR = false
                    if c == 10 { s[s.count - 1] += 1; continue }   // "\r\n": the line starts after the \n
                }
                switch c {
                case 13: afterCR = true; s.append(i + k + 1)
                case 10, 0x85, 0x2028, 0x2029: s.append(i + k + 1)
                default: break
                }
            }
            i += len
        }
        starts = s
    }

    /// 1-based line containing `loc`. Past the end → last line.
    public func line(at loc: Int) -> Int {
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= loc { lo = mid } else { hi = mid - 1 }
        }
        return lo + 1
    }

    /// Offset of 1-based line `n`, clamped to the first/last line.
    public func start(ofLine n: Int) -> Int { starts[max(0, min(n - 1, starts.count - 1))] }
}
