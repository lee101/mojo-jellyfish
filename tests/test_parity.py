from __future__ import annotations

import random
import string

import jellyfish as upstream
import pytest

import mojo_jellyfish as mojo


DISTANCE_VECTORS = [
    ("", "", 0),
    ("kitten", "sitting", 3),
    ("jellyfish", "smellyfish", 2),
    ("Saturday", "Sunday", 3),
    ("fish", "ifsh", 2),
    ("你好世界", "你好", 2),
]


@pytest.mark.parametrize("left,right,expected", DISTANCE_VECTORS)
def test_levenshtein_published_vectors(left, right, expected):
    assert mojo.levenshtein_distance(left, right) == expected
    assert mojo.levenshtein_distance(left, right) == upstream.levenshtein_distance(left, right)


@pytest.mark.parametrize("suffix_length", [1, 3, 7, 11, 17])
def test_levenshtein_ascii_simd_tail_parity(suffix_length):
    suffix = "a" * suffix_length
    left = "x" + suffix
    right = "y" + suffix
    assert mojo.levenshtein_distance(left, right) == upstream.levenshtein_distance(
        left, right
    )


@pytest.mark.parametrize(
    "left,right",
    [
        ("", ""),
        ("jellyfish", "jellyfihs"),
        ("fish", "ifsh"),
        ("CA", "ABC"),
        ("a cat", "an act"),
        ("abcd", "badc"),
        ("你好世界", "你世好界"),
    ],
)
def test_damerau_levenshtein_parity(left, right):
    assert mojo.damerau_levenshtein_distance(
        left, right
    ) == upstream.damerau_levenshtein_distance(left, right)


@pytest.mark.parametrize(
    "left,right,expected",
    [
        ("", "", 0),
        ("abc", "abc", 0),
        ("abc", "abd", 1),
        ("abc", "abcd", 1),
        ("toned", "roses", 3),
        ("你好", "你们好", 2),
    ],
)
def test_hamming_parity(left, right, expected):
    assert mojo.hamming_distance(left, right) == expected
    assert mojo.hamming_distance(left, right) == upstream.hamming_distance(left, right)


@pytest.mark.parametrize(
    "left,right",
    [
        ("", ""),
        ("MARTHA", "MARHTA"),
        ("DIXON", "DICKSONX"),
        ("JELLYFISH", "SMELLYFISH"),
        ("test", "test"),
        ("crate", "trace"),
        ("你好世界", "你好世间"),
    ],
)
def test_jaro_parity(left, right):
    assert mojo.jaro_similarity(left, right) == pytest.approx(
        upstream.jaro_similarity(left, right), abs=1e-15
    )


@pytest.mark.parametrize(
    "left,right",
    [
        ("", ""),
        ("MARTHA", "MARHTA"),
        ("DIXON", "DICKSONX"),
        ("JELLYFISH", "SMELLYFISH"),
        ("two long strings", "two long stringz"),
        ("crate", "trace"),
        ("你好世界", "你好世间"),
    ],
)
@pytest.mark.parametrize("long_tolerance", [False, True])
def test_jaro_winkler_parity(left, right, long_tolerance):
    assert mojo.jaro_winkler_similarity(
        left, right, long_tolerance
    ) == pytest.approx(
        upstream.jaro_winkler_similarity(left, right, long_tolerance),
        abs=1e-15,
    )


@pytest.mark.parametrize("long_tolerance", [0, 1, "yes", []])
def test_jaro_winkler_rejects_non_bool_long_tolerance(long_tolerance):
    with pytest.raises(TypeError):
        upstream.jaro_winkler_similarity("abc", "abd", long_tolerance)
    with pytest.raises(TypeError):
        mojo.jaro_winkler_similarity("abc", "abd", long_tolerance)


@pytest.mark.parametrize(
    "left,right,ngram_size",
    [
        ("hello world", "world hello", None),
        ("one two two", "one two", None),
        ("", "", None),
        ("abcdef", "abczef", 1),
        ("abcdef", "abcxyz", 2),
        ("abcdefgh", "abcdwxyz", 3),
        ("你好世界", "你好世间", 2),
    ],
)
def test_jaccard_parity(left, right, ngram_size):
    assert mojo.jaccard_similarity(left, right, ngram_size) == upstream.jaccard_similarity(
        left, right, ngram_size
    )


@pytest.mark.parametrize("repeat", [20, 20_000])
def test_jaccard_ascii_serial_and_parallel_parity(repeat):
    left = " ".join(("alpha", "beta", "gamma", "alpha") * repeat)
    right = " ".join(("beta", "delta", "gamma", "delta") * repeat)
    assert mojo.jaccard_similarity(left, right) == upstream.jaccard_similarity(
        left, right
    )


def test_jaccard_ascii_table_overflow_falls_back():
    left = " ".join(f"left{i}" for i in range(5_000))
    right = " ".join(f"right{i}" for i in range(5_000))
    assert mojo.jaccard_similarity(left, right) == upstream.jaccard_similarity(
        left, right
    )


@pytest.mark.parametrize(
    "value",
    [
        "",
        "Jellyfish",
        "Robert",
        "Rupert",
        "Ashcraft",
        "Tymczak",
        "Pfister",
        "José",
        "Straße",
    ],
)
def test_soundex_parity(value):
    assert mojo.soundex(value) == upstream.soundex(value)


@pytest.mark.parametrize(
    "value",
    [
        "",
        "Jellyfish",
        "Klumpz",
        "Clumps",
        "Xavier",
        "whale",
        "school",
        "abcdefghijklmnopqrstuvwxyz",
        "José",
        "Straße",
    ],
)
def test_metaphone_parity(value):
    assert mojo.metaphone(value) == upstream.metaphone(value)


@pytest.mark.parametrize(
    "value",
    ["a" * 7 + "schmidt" * 8, "mixed CASE metaphone input" * 6],
)
def test_metaphone_ascii_long_output_parity(value):
    assert mojo.metaphone(value) == upstream.metaphone(value)


@pytest.mark.parametrize(
    "value",
    [
        "",
        "John",
        "Jan",
        "Macdonald",
        "Knuth",
        "Pfister",
        "Schmidt",
        "Catherine",
        "Élodie",
    ],
)
def test_nysiis_parity(value):
    assert mojo.nysiis(value) == upstream.nysiis(value)


@pytest.mark.parametrize(
    "value",
    [
        "",
        "Jellyfish",
        "Smith",
        "Smyth",
        "Catherine",
        "Kathryn",
        "ÉÇÑΩ",
    ],
)
def test_match_rating_codex_parity(value):
    assert mojo.match_rating_codex(value) == upstream.match_rating_codex(value)


@pytest.mark.parametrize(
    "left,right",
    [
        ("Bryne", "Boern"),
        ("Smith", "Smyth"),
        ("Ed", "Ad"),
        ("Catherine", "Kathryn"),
        ("Michael", "Mike"),
        ("Tim", "Timothy"),
        ("ÉÇÑΩ", "ABCD"),
    ],
)
def test_match_rating_comparison_parity(left, right):
    assert mojo.match_rating_comparison(left, right) is upstream.match_rating_comparison(
        left, right
    )


def test_random_ascii_distance_parity():
    rng = random.Random(20260729)
    for _ in range(250):
        left = "".join(rng.choices(string.ascii_letters + " ", k=rng.randrange(25)))
        right = "".join(rng.choices(string.ascii_letters + " ", k=rng.randrange(25)))
        assert mojo.levenshtein_distance(left, right) == upstream.levenshtein_distance(
            left, right
        )
        assert mojo.damerau_levenshtein_distance(
            left, right
        ) == upstream.damerau_levenshtein_distance(left, right)
        assert mojo.hamming_distance(left, right) == upstream.hamming_distance(left, right)
        assert mojo.jaro_similarity(left, right) == upstream.jaro_similarity(left, right)
        assert mojo.jaro_winkler_similarity(
            left, right
        ) == upstream.jaro_winkler_similarity(left, right)


def test_random_ascii_phonetic_parity():
    rng = random.Random(1729)
    for _ in range(250):
        value = "".join(rng.choices(string.ascii_letters + " ", k=rng.randrange(30)))
        assert mojo.soundex(value) == upstream.soundex(value)
        assert mojo.metaphone(value) == upstream.metaphone(value)
        assert mojo.nysiis(value) == upstream.nysiis(value)
        assert mojo.match_rating_codex(value) == upstream.match_rating_codex(value)


@pytest.mark.parametrize(
    "left,right",
    [
        ("e\u0301", "é"),
        (
            "\U0001f468\u200d\U0001f469\u200d\U0001f467",
            "\U0001f468\u200d\U0001f469\u200d\U0001f466",
        ),
        ("\U0001f1fa\U0001f1f8a", "\U0001f1fa\U0001f1f8b"),
        ("क्", "क"),
        ("Z͑", "Z͑"),
    ],
)
def test_unicode_grapheme_distance_parity(left, right):
    for function in (
        "levenshtein_distance",
        "damerau_levenshtein_distance",
        "hamming_distance",
        "jaro_similarity",
        "jaro_winkler_similarity",
    ):
        assert getattr(mojo, function)(left, right) == getattr(upstream, function)(
            left, right
        )


@pytest.mark.parametrize(
    "function,args",
    [
        ("levenshtein_distance", (b"a", "a")),
        ("damerau_levenshtein_distance", ("a", b"a")),
        ("hamming_distance", (1, "1")),
        ("jaro_similarity", ("a", None)),
        ("jaro_winkler_similarity", ([], "a")),
        ("soundex", (b"ABC",)),
        ("metaphone", (123,)),
        ("nysiis", (None,)),
        ("match_rating_codex", (b"abc",)),
    ],
)
def test_non_string_arguments_raise_type_error(function, args):
    with pytest.raises(TypeError):
        getattr(mojo, function)(*args)


def test_match_rating_invalid_characters_match_upstream():
    with pytest.raises(ValueError):
        mojo.match_rating_codex("i’m")
    assert mojo.match_rating_comparison("i’m", "im") is None


def test_jaccard_rejects_invalid_ngram_size():
    with pytest.raises(ValueError):
        mojo.jaccard_similarity("abc", "abc", 0)
