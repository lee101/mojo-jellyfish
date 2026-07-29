"""Approximate and phonetic string matching backed by Mojo kernels."""

from __future__ import annotations

import ctypes
import unicodedata
from typing import Optional

import numpy as np
import regex

from ._lib import addr, lib

__all__ = [
    "damerau_levenshtein_distance",
    "hamming_distance",
    "jaccard_similarity",
    "jaro_similarity",
    "jaro_winkler_similarity",
    "levenshtein_distance",
    "match_rating_codex",
    "match_rating_comparison",
    "metaphone",
    "nysiis",
    "soundex",
]

_GRAPHEME = regex.compile(r"\X")
_JACCARD_SLOTS = 4096


def _require_string(value, name: str) -> str:
    if not isinstance(value, str):
        raise TypeError(f"{name} must be str, not {type(value).__name__}")
    return value


def _pair_tokens(s1: str, s2: str) -> tuple[np.ndarray, np.ndarray, int]:
    if s1.isascii() and s2.isascii():
        a = np.frombuffer(s1.encode("utf-32-le"), dtype=np.uint32)
        b = np.frombuffer(s2.encode("utf-32-le"), dtype=np.uint32)
        return a, b, 128

    first = _GRAPHEME.findall(s1)
    second = _GRAPHEME.findall(s2)
    ids: dict[str, int] = {}

    def token_id(token: str) -> int:
        value = ids.get(token)
        if value is None:
            value = len(ids) + 1
            ids[token] = value
        return value

    a = np.fromiter((token_id(token) for token in first), dtype=np.uint32, count=len(first))
    b = np.fromiter((token_id(token) for token in second), dtype=np.uint32, count=len(second))
    return a, b, len(ids) + 1


def _codepoints(s: str, *, normalize: bool = False, copy: bool = False) -> np.ndarray:
    value = s.upper()
    if normalize:
        value = unicodedata.normalize("NFKD", value)
    view = np.frombuffer(value.encode("utf-32-le"), dtype=np.uint32)
    return view.copy() if copy else view


def _decode(array: np.ndarray, length: int) -> str:
    return array[:length].astype("<u4", copy=False).tobytes().decode("utf-32-le")


def levenshtein_distance(s1: str, s2: str) -> int:
    s1 = _require_string(s1, "s1")
    s2 = _require_string(s2, "s2")
    if s1 == s2:
        return 0
    if s1.isascii() and s2.isascii() and min(len(s1), len(s2)) <= 64:
        a_bytes = s1.encode("ascii")
        b_bytes = s2.encode("ascii")
        if len(a_bytes) < len(b_bytes):
            a_bytes, b_bytes = b_bytes, a_bytes
        return int(
            lib().mj_levenshtein_ascii_short(
                a_bytes, b_bytes, len(a_bytes), len(b_bytes)
            )
        )
    a, b, _ = _pair_tokens(s1, s2)
    if len(a) < len(b):
        a, b = b, a
    scratch = np.empty(len(b) + 1, dtype=np.int64)
    return int(lib().mj_levenshtein(addr(a), addr(b), len(a), len(b), addr(scratch)))


def hamming_distance(s1: str, s2: str) -> int:
    s1 = _require_string(s1, "s1")
    s2 = _require_string(s2, "s2")
    a, b, _ = _pair_tokens(s1, s2)
    return int(lib().mj_hamming(addr(a), addr(b), len(a), len(b)))


def damerau_levenshtein_distance(s1: str, s2: str) -> int:
    s1 = _require_string(s1, "s1")
    s2 = _require_string(s2, "s2")
    if s1 == s2:
        return 0
    a, b, alphabet_size = _pair_tokens(s1, s2)
    score = np.empty((len(a) + 2) * (len(b) + 2), dtype=np.int64)
    last = np.empty(alphabet_size, dtype=np.int64)
    return int(
        lib().mj_damerau(
            addr(a),
            addr(b),
            len(a),
            len(b),
            addr(score),
            addr(last),
            alphabet_size,
        )
    )


def _jaro(s1: str, s2: str, mode: int) -> float:
    s1 = _require_string(s1, "s1")
    s2 = _require_string(s2, "s2")
    a, b, _ = _pair_tokens(s1, s2)
    flags_a = np.empty(max(len(a), 1), dtype=np.uint8)
    flags_b = np.empty(max(len(b), 1), dtype=np.uint8)
    return float(
        lib().mj_jaro(
            addr(a),
            addr(b),
            len(a),
            len(b),
            addr(flags_a),
            addr(flags_b),
            mode,
        )
    )


def jaro_similarity(s1: str, s2: str) -> float:
    return _jaro(s1, s2, 0)


def jaro_winkler_similarity(
    s1: str, s2: str, long_tolerance: Optional[bool] = None
) -> float:
    if long_tolerance is not None and not isinstance(long_tolerance, bool):
        raise TypeError(
            "argument 'long_tolerance' must be bool or None, "
            f"not {type(long_tolerance).__name__}"
        )
    return _jaro(s1, s2, 2 if long_tolerance else 1)


def jaccard_similarity(
    s1: str, s2: str, ngram_size: Optional[int] = None
) -> float:
    s1 = _require_string(s1, "s1")
    s2 = _require_string(s2, "s2")
    if ngram_size is None:
        if s1.isascii() and s2.isascii():
            a_bytes = s1.encode("ascii")
            b_bytes = s2.encode("ascii")
            starts_a = np.empty(_JACCARD_SLOTS, dtype=np.int64)
            lengths_a = np.empty(_JACCARD_SLOTS, dtype=np.int64)
            starts_b = np.empty(_JACCARD_SLOTS, dtype=np.int64)
            lengths_b = np.empty(_JACCARD_SLOTS, dtype=np.int64)
            result = float(
                lib().mj_jaccard_ascii_words(
                    a_bytes,
                    b_bytes,
                    len(a_bytes),
                    len(b_bytes),
                    addr(starts_a),
                    addr(lengths_a),
                    addr(starts_b),
                    addr(lengths_b),
                    _JACCARD_SLOTS,
                )
            )
            if result >= 0.0:
                return result
        first = set(s1.split())
        second = set(s2.split())
    else:
        if not isinstance(ngram_size, int):
            raise TypeError("ngram_size must be an integer or None")
        if ngram_size <= 0:
            raise ValueError("ngram_size must be greater than zero")
        first = {s1[i : i + ngram_size] for i in range(0, len(s1), ngram_size)}
        second = {s2[i : i + ngram_size] for i in range(0, len(s2), ngram_size)}
    intersection = len(first & second)
    union_size = len(first) + len(second) - intersection
    return intersection / union_size if union_size else 0.0


def soundex(s: str) -> str:
    s = _require_string(s, "s")
    if not s:
        return ""
    if s.isascii():
        source = s.upper().encode("ascii")
        packed = int(lib().mj_soundex_ascii_packed(source, len(source)))
        return packed.to_bytes(4, "little").decode("ascii")
    source = _codepoints(s, normalize=True)
    dest = np.empty(4, dtype=np.uint32)
    length = lib().mj_soundex(addr(source), len(source), addr(dest))
    return _decode(dest, length)


def metaphone(s: str) -> str:
    s = _require_string(s, "s")
    if not s:
        return ""
    if s.isascii():
        source = s.upper().encode("ascii")
        if len(source) <= 32:
            packed = int(lib().mj_metaphone_ascii_packed(source, len(source)))
            if packed >> 63 == 0:
                encoded = packed.to_bytes(8, "little")
                end = encoded.find(b"\0")
                return encoded[: end if end >= 0 else 8].decode("ascii")
        dest = ctypes.create_string_buffer(max(2 * len(source) + 1, 1))
        length = lib().mj_metaphone_ascii(source, len(source), dest)
        return dest.raw[:length].decode("ascii")
    source = _codepoints(s, normalize=True)
    dest = np.empty(max(2 * len(source) + 1, 1), dtype=np.uint32)
    length = lib().mj_metaphone(addr(source), len(source), addr(dest))
    return _decode(dest, length)


def nysiis(s: str) -> str:
    s = _require_string(s, "s")
    source = _codepoints(s, copy=True)
    dest = np.empty(max(2 * len(source) + 1, 1), dtype=np.uint32)
    length = lib().mj_nysiis(addr(source), len(source), addr(dest))
    return _decode(dest, length)


def match_rating_codex(s: str) -> str:
    s = _require_string(s, "s")
    if not all(character.isalpha() or character == " " for character in s):
        raise ValueError("Strings must only contain alphabetical characters")
    source = _codepoints(s)
    dest = np.empty(max(len(source), 1), dtype=np.uint32)
    length = lib().mj_match_rating_codex(addr(source), len(source), addr(dest))
    result = _decode(dest, length)
    if len(result.encode("utf-8")) > 6 and len(result) <= 6:
        return result[:3] + result[-3:]
    return result


def match_rating_comparison(s1: str, s2: str) -> Optional[bool]:
    s1 = _require_string(s1, "s1")
    s2 = _require_string(s2, "s2")
    try:
        codex1 = match_rating_codex(s1)
        codex2 = match_rating_codex(s2)
    except ValueError:
        return None
    size1 = len(codex1.encode("utf-8"))
    size2 = len(codex2.encode("utf-8"))
    if size1 > size2:
        longer, shorter = codex1, codex2
        longer_size, shorter_size = size1, size2
    else:
        longer, shorter = codex2, codex1
        longer_size, shorter_size = size2, size1
    if longer_size - shorter_size >= 3:
        return None

    residual_long = []
    residual_short = []
    for index in range(len(longer)):
        left = longer[index]
        right = shorter[index] if index < len(shorter) else None
        if left != right:
            residual_long.append(left)
            if right is not None:
                residual_short.append(right)
    unmatched = max(
        sum(a != b for a, b in zip(residual_long[::-1], residual_short[::-1]))
        + max(0, len(residual_long) - len(residual_short)),
        sum(a != b for a, b in zip(residual_long[::-1], residual_short[::-1]))
        + max(0, len(residual_short) - len(residual_long)),
    )
    score = 6 - unmatched
    length_sum = longer_size + shorter_size
    minimum = 5 if length_sum <= 4 else 4 if length_sum <= 7 else 3 if length_sum <= 11 else 2
    return score >= minimum
