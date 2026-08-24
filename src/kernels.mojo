"""String-distance and phonetic kernels exposed through a small C ABI."""

from std.memory import stack_allocation
from std.sys import simd_width_of


comptime U8Ptr = UnsafePointer[UInt8, AnyOrigin[mut=True]]
comptime U32Ptr = UnsafePointer[UInt32, AnyOrigin[mut=True]]
comptime I64Ptr = UnsafePointer[Int64, AnyOrigin[mut=True]]
comptime I64StackPtr = UnsafePointer[Int64, MutUntrackedOrigin]


def min3(a: Int64, b: Int64, c: Int64) -> Int64:
    var value = a if a < b else b
    return value if value < c else c


def replacement(c: UInt32) -> UInt32:
    if c == 66 or c == 70 or c == 80 or c == 86:
        return 49
    if (
        c == 67
        or c == 71
        or c == 74
        or c == 75
        or c == 81
        or c == 83
        or c == 88
        or c == 90
    ):
        return 50
    if c == 68 or c == 84:
        return 51
    if c == 76:
        return 52
    if c == 77 or c == 78:
        return 53
    if c == 82:
        return 54
    return 42


def is_vowel(c: UInt32) -> Bool:
    return c == 65 or c == 69 or c == 73 or c == 79 or c == 85


def is_iey(c: UInt32) -> Bool:
    return c == 73 or c == 69 or c == 89


def ascii_upper(c: UInt8) -> UInt8:
    return c - 32 if c >= 97 and c <= 122 else c


def starts2(s: U32Ptr, n: Int, a: UInt32, b: UInt32) -> Bool:
    return n >= 2 and s[0] == a and s[1] == b


def starts3(s: U32Ptr, n: Int, a: UInt32, b: UInt32, c: UInt32) -> Bool:
    return n >= 3 and s[0] == a and s[1] == b and s[2] == c


def ends2(s: U32Ptr, n: Int, a: UInt32, b: UInt32) -> Bool:
    return n >= 2 and s[n - 2] == a and s[n - 1] == b


def levenshtein(a: U32Ptr, b: U32Ptr, n: Int, m: Int, row: I64Ptr) -> Int:
    var a0 = 0
    var b0 = 0
    var an = n
    var bm = m
    while a0 < an and b0 < bm and a[a0] == b[b0]:
        a0 += 1
        b0 += 1
    while an > a0 and bm > b0 and a[an - 1] == b[bm - 1]:
        an -= 1
        bm -= 1
    var nr = an - a0
    var nc = bm - b0
    if nr == 0:
        return nc
    if nc == 0:
        return nr

    for j in range(nc + 1):
        row[j] = Int64(j)
    for i in range(1, nr + 1):
        var diagonal = row[0]
        row[0] = Int64(i)
        for j in range(1, nc + 1):
            var above = row[j]
            var cost: Int64 = 0 if a[a0 + i - 1] == b[b0 + j - 1] else 1
            row[j] = min3(above + 1, row[j - 1] + 1, diagonal + cost)
            diagonal = above
    return Int(row[nc])


def levenshtein_ascii(
    a: U8Ptr, b: U8Ptr, n: Int, m: Int, row: I64StackPtr
) -> Int:
    comptime W = simd_width_of[DType.float64]()
    var a0 = 0
    var b0 = 0
    var an = n
    var bm = m
    while an - a0 >= W and bm - b0 >= W:
        if a.load[width=W](a0) != b.load[width=W](b0):
            break
        a0 += W
        b0 += W
    while a0 < an and b0 < bm and a[a0] == b[b0]:
        a0 += 1
        b0 += 1
    while an - a0 >= W and bm - b0 >= W:
        if a.load[width=W](an - W) != b.load[width=W](bm - W):
            break
        an -= W
        bm -= W
    while an > a0 and bm > b0 and a[an - 1] == b[bm - 1]:
        an -= 1
        bm -= 1
    var nr = an - a0
    var nc = bm - b0
    if nr == 0:
        return nc
    if nc == 0:
        return nr

    for j in range(nc + 1):
        row[j] = Int64(j)
    for i in range(1, nr + 1):
        var diagonal = row[0]
        row[0] = Int64(i)
        for j in range(1, nc + 1):
            var above = row[j]
            var cost: Int64 = 0 if a[a0 + i - 1] == b[b0 + j - 1] else 1
            row[j] = min3(above + 1, row[j - 1] + 1, diagonal + cost)
            diagonal = above
    return Int(row[nc])


def hamming(a: U32Ptr, b: U32Ptr, n: Int, m: Int) -> Int:
    var common = n if n < m else m
    var distance = n - m if n > m else m - n
    for i in range(common):
        if a[i] != b[i]:
            distance += 1
    return distance


def is_ascii_space(c: UInt8) -> Bool:
    return (c >= 9 and c <= 13) or (c >= 28 and c <= 32)


def word_hash(s: U8Ptr, start: Int, length: Int) -> UInt64:
    var value = UInt64(1469598103934665603)
    for i in range(length):
        value = (value ^ UInt64(s[start + i])) * UInt64(1099511628211)
    return value


def words_equal(
    a: U8Ptr, a_start: Int, b: U8Ptr, b_start: Int, length: Int
) -> Bool:
    comptime W = simd_width_of[DType.float64]()
    var i = 0
    while i + W <= length:
        if a.load[width=W](a_start + i) != b.load[width=W](b_start + i):
            return False
        i += W
    while i < length:
        if a[a_start + i] != b[b_start + i]:
            return False
        i += 1
    return True


def clear_word_table(starts: I64Ptr, slots: Int):
    comptime W = simd_width_of[DType.float64]()
    var fill = SIMD[DType.int64, W](-1)
    var i = 0
    while i + W <= slots:
        starts.store(i, fill)
        i += W
    while i < slots:
        starts[i] = -1
        i += 1


def build_word_set(
    s: U8Ptr,
    n: Int,
    starts: I64Ptr,
    lengths: I64Ptr,
    slots: Int,
) -> Int:
    clear_word_table(starts, slots)
    var unique = 0
    var i = 0
    while i < n:
        while i < n and is_ascii_space(s[i]):
            i += 1
        if i == n:
            break
        var start = i
        while i < n and not is_ascii_space(s[i]):
            i += 1
        var length = i - start
        var slot = Int(word_hash(s, start, length) & UInt64(slots - 1))
        var probes = 0
        while probes < slots:
            var existing = Int(starts[slot])
            if existing < 0:
                starts[slot] = Int64(start)
                lengths[slot] = Int64(length)
                unique += 1
                break
            if (
                Int(lengths[slot]) == length
                and words_equal(s, start, s, existing, length)
            ):
                break
            slot = (slot + 1) & (slots - 1)
            probes += 1
        if probes == slots:
            return -1
    return unique


def word_set_contains(
    table_text: U8Ptr,
    starts: I64Ptr,
    lengths: I64Ptr,
    slots: Int,
    text: U8Ptr,
    start: Int,
    length: Int,
) -> Bool:
    var slot = Int(word_hash(text, start, length) & UInt64(slots - 1))
    var probes = 0
    while probes < slots:
        var existing = Int(starts[slot])
        if existing < 0:
            return False
        if (
            Int(lengths[slot]) == length
            and words_equal(table_text, existing, text, start, length)
        ):
            return True
        slot = (slot + 1) & (slots - 1)
        probes += 1
    return False


def jaccard_ascii_words(
    a: U8Ptr,
    b: U8Ptr,
    n: Int,
    m: Int,
    starts_a: I64Ptr,
    lengths_a: I64Ptr,
    starts_b: I64Ptr,
    lengths_b: I64Ptr,
    slots: Int,
) -> Float64:
    var counts = stack_allocation[2, DType.int64]()
    counts[0] = Int64(build_word_set(a, n, starts_a, lengths_a, slots))
    counts[1] = Int64(build_word_set(b, m, starts_b, lengths_b, slots))

    var count_a = Int(counts[0])
    var count_b = Int(counts[1])
    if count_a < 0 or count_b < 0:
        return -1.0
    var intersection = 0
    for slot in range(slots):
        var start = Int(starts_a[slot])
        if start >= 0:
            var length = Int(lengths_a[slot])
            if word_set_contains(
                b, starts_b, lengths_b, slots, a, start, length
            ):
                intersection += 1
    var union = count_a + count_b - intersection
    if union == 0:
        return 0.0
    return Float64(intersection) / Float64(union)


def damerau(
    a: U32Ptr,
    b: U32Ptr,
    n: Int,
    m: Int,
    score: I64Ptr,
    last: I64Ptr,
    alphabet_size: Int,
) -> Int:
    var cols = m + 2
    var infinite = n + m
    for i in range((n + 2) * cols):
        score[i] = 0
    for i in range(alphabet_size):
        last[i] = 0

    score[0] = Int64(infinite)
    for i in range(n + 1):
        score[(i + 1) * cols] = Int64(infinite)
        score[(i + 1) * cols + 1] = Int64(i)
    for j in range(m + 1):
        score[j + 1] = Int64(infinite)
        score[cols + j + 1] = Int64(j)

    for i in range(1, n + 1):
        var match_col = 0
        for j in range(1, m + 1):
            var previous_row = Int(last[Int(b[j - 1])])
            var previous_col = match_col
            var cost: Int64 = 1
            if a[i - 1] == b[j - 1]:
                cost = 0
                match_col = j
            var substitution = score[i * cols + j] + cost
            var insertion = score[(i + 1) * cols + j] + 1
            var deletion = score[i * cols + j + 1] + 1
            var transposition = (
                score[previous_row * cols + previous_col]
                + Int64(i - previous_row - 1)
                + 1
                + Int64(j - previous_col - 1)
            )
            score[(i + 1) * cols + j + 1] = min3(
                substitution,
                insertion,
                deletion if deletion < transposition else transposition,
            )
        last[Int(a[i - 1])] = Int64(i)
    return Int(score[(n + 1) * cols + m + 1])


def jaro(
    a: U32Ptr,
    b: U32Ptr,
    n: Int,
    m: Int,
    flags_a: U8Ptr,
    flags_b: U8Ptr,
    winkler: Bool,
    long_tolerance: Bool,
) -> Float64:
    if n == 0 or m == 0:
        return 0.0
    for i in range(n):
        flags_a[i] = 0
    for i in range(m):
        flags_b[i] = 0

    var minimum = n if n < m else m
    var maximum = n if n > m else m
    var search_range = maximum // 2
    if search_range > 0:
        search_range -= 1
    var common = 0

    for i in range(n):
        var low = i - search_range if i > search_range else 0
        var high = i + search_range
        if high >= m:
            high = m - 1
        for j in range(low, high + 1):
            if flags_b[j] == 0 and b[j] == a[i]:
                flags_a[i] = 1
                flags_b[j] = 1
                common += 1
                break

    if common == 0:
        return 0.0

    var k = 0
    var transpositions = 0
    for i in range(n):
        if flags_a[i] != 0:
            while k < m and flags_b[k] == 0:
                k += 1
            if a[i] != b[k]:
                transpositions += 1
            k += 1

    var trans = Float64(transpositions // 2)
    var commonf = Float64(common)
    var nf = Float64(n)
    var mf = Float64(m)
    var weight = (
        commonf / nf + commonf / mf + (commonf - trans) / commonf
    ) / 3.0

    if winkler and weight > 0.7:
        var prefix = 0
        var prefix_limit = minimum if minimum < 4 else 4
        while prefix < prefix_limit and a[prefix] == b[prefix]:
            prefix += 1
        var prefixf = Float64(prefix)
        if prefix > 0:
            weight += prefixf * 0.1 * (1.0 - weight)
        if (
            long_tolerance
            and minimum > 4
            and common > prefix + 1
            and 2 * common >= minimum + prefix
        ):
            weight += (
                (1.0 - weight)
                * (commonf - prefixf - 1.0)
                / (nf + mf - prefixf * 2.0 + 2.0)
            )
    return weight


def soundex_kernel(s: U32Ptr, n: Int, dest: U32Ptr) -> Int:
    if n == 0:
        return 0
    dest[0] = s[0]
    var written = 1
    var previous = replacement(s[0])
    for i in range(1, n):
        var code = replacement(s[i])
        if code != 42:
            if code != previous:
                dest[written] = code
                written += 1
                if written == 4:
                    return written
            previous = code
        elif s[i] != 72 and s[i] != 87:
            previous = 42
    while written < 4:
        dest[written] = 48
        written += 1
    return written


def soundex_ascii_packed(s: U8Ptr, n: Int) -> UInt32:
    var first = ascii_upper(s[0])
    var result = UInt32(first)
    var written = 1
    var previous = replacement(UInt32(first))
    for i in range(1, n):
        var current = ascii_upper(s[i])
        var code = replacement(UInt32(current))
        if code != 42:
            if code != previous:
                result |= code << UInt32(8 * written)
                written += 1
                if written == 4:
                    return result
            previous = code
        elif current != 72 and current != 87:
            previous = 42
    while written < 4:
        result |= UInt32(48) << UInt32(8 * written)
        written += 1
    return result


def metaphone_kernel(s: U32Ptr, n: Int, dest: U32Ptr) -> Int:
    if n == 0:
        return 0
    var start = 0
    if (
        starts2(s, n, 75, 78)
        or starts2(s, n, 71, 78)
        or starts2(s, n, 80, 78)
        or starts2(s, n, 87, 82)
        or starts2(s, n, 65, 69)
    ):
        start = 1
    var written = 0
    var i = start
    while i < n:
        var c = s[i]
        var nxt: UInt32 = s[i + 1] if i + 1 < n else 42
        var nxt2: UInt32 = s[i + 2] if i + 2 < n else 42
        if c == nxt and c != 67:
            i += 1
            continue

        if is_vowel(c):
            if i == start or (i > 0 and s[i - 1] == 32):
                dest[written] = c
                written += 1
        elif c == 66:
            if (i == start or s[i - 1] != 77) or nxt != 42:
                dest[written] = 66
                written += 1
        elif c == 67:
            if (nxt == 73 and nxt2 == 65) or nxt == 72:
                i += 1
                dest[written] = 88
                written += 1
            elif is_iey(nxt):
                i += 1
                dest[written] = 83
                written += 1
            else:
                dest[written] = 75
                written += 1
        elif c == 68:
            if nxt == 71 and is_iey(nxt2):
                i += 2
                dest[written] = 74
                written += 1
            else:
                dest[written] = 84
                written += 1
        elif c == 70 or c == 74 or c == 76 or c == 77 or c == 78 or c == 82:
            dest[written] = c
            written += 1
        elif c == 71:
            if is_iey(nxt):
                dest[written] = 74
                written += 1
            elif (
                (nxt == 72 and nxt2 != 42 and not is_vowel(nxt2))
                or (nxt == 78 and nxt2 == 42)
            ):
                i += 1
            else:
                dest[written] = 75
                written += 1
        elif c == 72:
            if i == start or is_vowel(nxt) or (i > 0 and not is_vowel(s[i - 1])):
                dest[written] = 72
                written += 1
        elif c == 75:
            if i == start or s[i - 1] != 67:
                dest[written] = 75
                written += 1
        elif c == 80:
            if nxt == 72:
                i += 1
                dest[written] = 70
            else:
                dest[written] = 80
            written += 1
        elif c == 81:
            dest[written] = 75
            written += 1
        elif c == 83:
            if nxt == 72:
                i += 1
                dest[written] = 88
                written += 1
            elif nxt == 73 and (nxt2 == 79 or nxt2 == 65):
                i += 2
                dest[written] = 88
                written += 1
            else:
                dest[written] = 83
                written += 1
        elif c == 84:
            if nxt == 73 and (nxt2 == 79 or nxt2 == 65):
                dest[written] = 88
                written += 1
            elif nxt == 72:
                i += 1
                dest[written] = 48
                written += 1
            elif nxt != 67 or nxt2 != 72:
                dest[written] = 84
                written += 1
        elif c == 86:
            dest[written] = 70
            written += 1
        elif c == 87:
            if i == start and nxt == 72:
                i += 1
                dest[written] = 87
                written += 1
            elif is_vowel(nxt):
                dest[written] = 87
                written += 1
        elif c == 88:
            if i == start:
                dest[written] = 88 if (
                    nxt == 72 or (nxt == 73 and (nxt2 == 79 or nxt2 == 65))
                ) else 83
                written += 1
            else:
                dest[written] = 75
                dest[written + 1] = 83
                written += 2
        elif c == 89:
            if is_vowel(nxt):
                dest[written] = 89
                written += 1
        elif c == 90:
            dest[written] = 83
            written += 1
        elif c == 32:
            if written > 0 and dest[written - 1] != 32:
                dest[written] = 32
                written += 1
        i += 1
    return written


def metaphone_ascii_kernel(s: U8Ptr, n: Int, dest: U8Ptr) -> Int:
    if n == 0:
        return 0
    var start = 0
    if (
        (n >= 2 and ascii_upper(s[0]) == 75 and ascii_upper(s[1]) == 78)
        or (n >= 2 and ascii_upper(s[0]) == 71 and ascii_upper(s[1]) == 78)
        or (n >= 2 and ascii_upper(s[0]) == 80 and ascii_upper(s[1]) == 78)
        or (n >= 2 and ascii_upper(s[0]) == 87 and ascii_upper(s[1]) == 82)
        or (n >= 2 and ascii_upper(s[0]) == 65 and ascii_upper(s[1]) == 69)
    ):
        start = 1
    var written = 0
    var i = start
    while i < n:
        var c = UInt32(ascii_upper(s[i]))
        var nxt: UInt32 = UInt32(ascii_upper(s[i + 1])) if i + 1 < n else 42
        var nxt2: UInt32 = UInt32(ascii_upper(s[i + 2])) if i + 2 < n else 42
        if c == nxt and c != 67:
            i += 1
            continue

        if is_vowel(c):
            if i == start or (i > 0 and ascii_upper(s[i - 1]) == 32):
                dest[written] = UInt8(c)
                written += 1
        elif c == 66:
            if (i == start or ascii_upper(s[i - 1]) != 77) or nxt != 42:
                dest[written] = 66
                written += 1
        elif c == 67:
            if (nxt == 73 and nxt2 == 65) or nxt == 72:
                i += 1
                dest[written] = 88
                written += 1
            elif is_iey(nxt):
                i += 1
                dest[written] = 83
                written += 1
            else:
                dest[written] = 75
                written += 1
        elif c == 68:
            if nxt == 71 and is_iey(nxt2):
                i += 2
                dest[written] = 74
                written += 1
            else:
                dest[written] = 84
                written += 1
        elif c == 70 or c == 74 or c == 76 or c == 77 or c == 78 or c == 82:
            dest[written] = UInt8(c)
            written += 1
        elif c == 71:
            if is_iey(nxt):
                dest[written] = 74
                written += 1
            elif (
                (nxt == 72 and nxt2 != 42 and not is_vowel(nxt2))
                or (nxt == 78 and nxt2 == 42)
            ):
                i += 1
            else:
                dest[written] = 75
                written += 1
        elif c == 72:
            if i == start or is_vowel(nxt) or (
                i > 0 and not is_vowel(UInt32(ascii_upper(s[i - 1])))
            ):
                dest[written] = 72
                written += 1
        elif c == 75:
            if i == start or ascii_upper(s[i - 1]) != 67:
                dest[written] = 75
                written += 1
        elif c == 80:
            if nxt == 72:
                i += 1
                dest[written] = 70
            else:
                dest[written] = 80
            written += 1
        elif c == 81:
            dest[written] = 75
            written += 1
        elif c == 83:
            if nxt == 72:
                i += 1
                dest[written] = 88
                written += 1
            elif nxt == 73 and (nxt2 == 79 or nxt2 == 65):
                i += 2
                dest[written] = 88
                written += 1
            else:
                dest[written] = 83
                written += 1
        elif c == 84:
            if nxt == 73 and (nxt2 == 79 or nxt2 == 65):
                dest[written] = 88
                written += 1
            elif nxt == 72:
                i += 1
                dest[written] = 48
                written += 1
            elif nxt != 67 or nxt2 != 72:
                dest[written] = 84
                written += 1
        elif c == 86:
            dest[written] = 70
            written += 1
        elif c == 87:
            if i == start and nxt == 72:
                i += 1
                dest[written] = 87
                written += 1
            elif is_vowel(nxt):
                dest[written] = 87
                written += 1
        elif c == 88:
            if i == start:
                dest[written] = 88 if (
                    nxt == 72 or (nxt == 73 and (nxt2 == 79 or nxt2 == 65))
                ) else 83
                written += 1
            else:
                dest[written] = 75
                dest[written + 1] = 83
                written += 2
        elif c == 89:
            if is_vowel(nxt):
                dest[written] = 89
                written += 1
        elif c == 90:
            dest[written] = 83
            written += 1
        elif c == 32:
            if written > 0 and dest[written - 1] != 32:
                dest[written] = 32
                written += 1
        i += 1
    return written


def nysiis_kernel(s: U32Ptr, n: Int, dest: U32Ptr) -> Int:
    if n == 0:
        return 0
    var length = n
    if starts3(s, length, 77, 65, 67):
        s[1] = 67
    elif starts2(s, length, 75, 78):
        for i in range(length - 1):
            s[i] = s[i + 1]
        length -= 1
    elif s[0] == 75:
        s[0] = 67
    elif starts2(s, length, 80, 72) or starts2(s, length, 80, 70):
        s[0] = 70
        s[1] = 70
    elif starts3(s, length, 83, 67, 72):
        s[1] = 83
        s[2] = 83

    if ends2(s, length, 73, 69) or ends2(s, length, 69, 69):
        length -= 1
        s[length - 1] = 89
    elif (
        ends2(s, length, 68, 84)
        or ends2(s, length, 82, 84)
        or ends2(s, length, 82, 68)
        or ends2(s, length, 78, 84)
        or ends2(s, length, 78, 68)
    ):
        length -= 1
        s[length - 1] = 68

    dest[0] = s[0]
    var written = 1
    var i = 1
    while i < length:
        var c = s[i]
        var c1: UInt32 = 0
        var c2: UInt32 = 0
        var produced = 1
        if c == 69 and i + 1 < length and s[i + 1] == 86:
            i += 1
            c1 = 65
            c2 = 70
            produced = 2
        elif is_vowel(c):
            c1 = 65
        elif c == 81:
            c1 = 71
        elif c == 90:
            c1 = 83
        elif c == 77:
            c1 = 78
        elif c == 75:
            c1 = 78 if i + 1 < length and s[i + 1] == 78 else 67
        elif c == 83 and i + 2 < length and s[i + 1] == 67 and s[i + 2] == 72:
            i += 2
            c1 = 83
            c2 = 83
            produced = 2
        elif c == 80 and i + 1 < length and s[i + 1] == 72:
            i += 1
            c1 = 70
        elif c == 72 and (
            not is_vowel(s[i - 1])
            or (i + 1 < length and not is_vowel(s[i + 1]))
            or i + 1 == length
        ):
            c1 = 65 if is_vowel(s[i - 1]) else s[i - 1]
        elif c == 87 and is_vowel(s[i - 1]):
            c1 = s[i - 1]
        else:
            c1 = c

        var last_produced = c2 if produced == 2 else c1
        if last_produced != dest[written - 1]:
            dest[written] = c1
            written += 1
            if produced == 2:
                dest[written] = c2
                written += 1
        i += 1

    if written > 1 and dest[written - 1] == 83:
        written -= 1
    if written >= 2 and dest[written - 2] == 65 and dest[written - 1] == 89:
        dest[written - 2] = 89
        written -= 1
    if written > 1 and dest[written - 1] == 65:
        written -= 1
    return written


def match_rating_codex_kernel(s: U32Ptr, n: Int, dest: U32Ptr) -> Int:
    var written = 0
    var previous: UInt32 = 126
    for i in range(n):
        var c = s[i]
        var vowel = is_vowel(c)
        if (c != 32 and i == 0 and vowel) or (not vowel and c != previous):
            dest[written] = c
            written += 1
        previous = c
    if written > 6:
        dest[3] = dest[written - 3]
        dest[4] = dest[written - 2]
        dest[5] = dest[written - 1]
        return 6
    return written


@export("mj_levenshtein")
def mj_levenshtein(
    a_addr: Int, b_addr: Int, n: Int, m: Int, scratch_addr: Int
) abi("C") -> Int:
    if n == 0:
        return m
    if m == 0:
        return n
    return levenshtein(
        U32Ptr(unsafe_from_address=a_addr),
        U32Ptr(unsafe_from_address=b_addr),
        n,
        m,
        I64Ptr(unsafe_from_address=scratch_addr),
    )


@export("mj_levenshtein_ascii_short")
def mj_levenshtein_ascii_short(
    a_addr: Int, b_addr: Int, n: Int, m: Int
) abi("C") -> Int:
    if n == 0:
        return m
    if m == 0:
        return n
    var row = stack_allocation[65, DType.int64]()
    return levenshtein_ascii(
        U8Ptr(unsafe_from_address=a_addr),
        U8Ptr(unsafe_from_address=b_addr),
        n,
        m,
        row,
    )


@export("mj_hamming")
def mj_hamming(a_addr: Int, b_addr: Int, n: Int, m: Int) abi("C") -> Int:
    if n == 0:
        return m
    if m == 0:
        return n
    return hamming(
        U32Ptr(unsafe_from_address=a_addr),
        U32Ptr(unsafe_from_address=b_addr),
        n,
        m,
    )


@export("mj_damerau")
def mj_damerau(
    a_addr: Int,
    b_addr: Int,
    n: Int,
    m: Int,
    score_addr: Int,
    last_addr: Int,
    alphabet_size: Int,
) abi("C") -> Int:
    if n == 0:
        return m
    if m == 0:
        return n
    return damerau(
        U32Ptr(unsafe_from_address=a_addr),
        U32Ptr(unsafe_from_address=b_addr),
        n,
        m,
        I64Ptr(unsafe_from_address=score_addr),
        I64Ptr(unsafe_from_address=last_addr),
        alphabet_size,
    )


@export("mj_jaro")
def mj_jaro(
    a_addr: Int,
    b_addr: Int,
    n: Int,
    m: Int,
    flags_a_addr: Int,
    flags_b_addr: Int,
    mode: Int,
) abi("C") -> Float64:
    if n == 0 or m == 0:
        return 0.0
    return jaro(
        U32Ptr(unsafe_from_address=a_addr),
        U32Ptr(unsafe_from_address=b_addr),
        n,
        m,
        U8Ptr(unsafe_from_address=flags_a_addr),
        U8Ptr(unsafe_from_address=flags_b_addr),
        mode > 0,
        mode > 1,
    )


@export("mj_jaccard_ascii_words")
def mj_jaccard_ascii_words(
    a_addr: Int,
    b_addr: Int,
    n: Int,
    m: Int,
    starts_a_addr: Int,
    lengths_a_addr: Int,
    starts_b_addr: Int,
    lengths_b_addr: Int,
    slots: Int,
) abi("C") -> Float64:
    return jaccard_ascii_words(
        U8Ptr(unsafe_from_address=a_addr),
        U8Ptr(unsafe_from_address=b_addr),
        n,
        m,
        I64Ptr(unsafe_from_address=starts_a_addr),
        I64Ptr(unsafe_from_address=lengths_a_addr),
        I64Ptr(unsafe_from_address=starts_b_addr),
        I64Ptr(unsafe_from_address=lengths_b_addr),
        slots,
    )


@export("mj_soundex")
def mj_soundex(s_addr: Int, n: Int, dest_addr: Int) abi("C") -> Int:
    if n == 0:
        return 0
    return soundex_kernel(
        U32Ptr(unsafe_from_address=s_addr),
        n,
        U32Ptr(unsafe_from_address=dest_addr),
    )


@export("mj_soundex_ascii_packed")
def mj_soundex_ascii_packed(s_addr: Int, n: Int) abi("C") -> UInt32:
    if n == 0:
        return 0
    return soundex_ascii_packed(U8Ptr(unsafe_from_address=s_addr), n)


@export("mj_metaphone")
def mj_metaphone(s_addr: Int, n: Int, dest_addr: Int) abi("C") -> Int:
    if n == 0:
        return 0
    return metaphone_kernel(
        U32Ptr(unsafe_from_address=s_addr),
        n,
        U32Ptr(unsafe_from_address=dest_addr),
    )


@export("mj_metaphone_ascii")
def mj_metaphone_ascii(s_addr: Int, n: Int, dest_addr: Int) abi("C") -> Int:
    if n == 0:
        return 0
    return metaphone_ascii_kernel(
        U8Ptr(unsafe_from_address=s_addr),
        n,
        U8Ptr(unsafe_from_address=dest_addr),
    )


@export("mj_metaphone_ascii_packed")
def mj_metaphone_ascii_packed(s_addr: Int, n: Int) abi("C") -> UInt64:
    if n == 0:
        return 0
    if n > 32:
        return UInt64(1) << UInt64(63)
    var dest = stack_allocation[65, DType.uint8]()
    var length = metaphone_ascii_kernel(
        U8Ptr(unsafe_from_address=s_addr),
        n,
        dest.as_unsafe_any_origin(),
    )
    if length > 8:
        return UInt64(1) << UInt64(63)
    var result = UInt64(0)
    for i in range(length):
        result |= UInt64(dest[i]) << UInt64(8 * i)
    return result


@export("mj_nysiis")
def mj_nysiis(s_addr: Int, n: Int, dest_addr: Int) abi("C") -> Int:
    if n == 0:
        return 0
    return nysiis_kernel(
        U32Ptr(unsafe_from_address=s_addr),
        n,
        U32Ptr(unsafe_from_address=dest_addr),
    )


@export("mj_match_rating_codex")
def mj_match_rating_codex(s_addr: Int, n: Int, dest_addr: Int) abi("C") -> Int:
    if n == 0:
        return 0
    return match_rating_codex_kernel(
        U32Ptr(unsafe_from_address=s_addr),
        n,
        U32Ptr(unsafe_from_address=dest_addr),
    )
