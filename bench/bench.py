"""Benchmarks against the installed upstream jellyfish package."""

from __future__ import annotations

import gc
import math
import os
import platform
import random
import sys
import time
from importlib.metadata import version

sys.path.insert(
    0,
    os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "python",
    ),
)

import jellyfish as upstream  # noqa: E402
import mojo_jellyfish as mojo  # noqa: E402


def best_time(function, number: int, repeat: int = 3) -> float:
    function()
    best = math.inf
    gc.disable()
    try:
        for _ in range(repeat):
            start = time.perf_counter()
            for _ in range(number):
                function()
            best = min(best, (time.perf_counter() - start) / number)
    finally:
        gc.enable()
    return best


def format_time(seconds: float) -> str:
    if seconds < 1e-6:
        return f"{seconds * 1e9:.1f} ns"
    if seconds < 1e-3:
        return f"{seconds * 1e6:.1f} us"
    return f"{seconds * 1e3:.2f} ms"


def cpu_name() -> str:
    try:
        with open("/proc/cpuinfo", encoding="utf-8") as handle:
            for line in handle:
                if line.startswith("model name"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or "unknown CPU"


def mutation_pair(length: int, seed: int) -> tuple[str, str]:
    rng = random.Random(seed)
    first = "".join(rng.choices("abcdefghijklmnopqrstuvwxyz", k=length))
    second = list(first)
    for _ in range(max(1, length // 50)):
        index = rng.randrange(length)
        second[index] = rng.choice("abcdefghijklmnopqrstuvwxyz")
    return first, "".join(second)


def main() -> None:
    short_a, short_b = "Dunningham", "Cunningham"
    lev_a, lev_b = mutation_pair(2048, 1)
    dam_a, dam_b = mutation_pair(512, 2)
    jaro_a, jaro_b = mutation_pair(2_000, 3)
    ham_a, ham_b = mutation_pair(1_000_000, 4)
    text_a = " ".join(f"token{i % 1200}" for i in range(100_000))
    text_b = " ".join(f"token{i % 1300}" for i in range(100_000))

    cases = [
        (
            "Levenshtein, 10-char names",
            lambda: mojo.levenshtein_distance(short_a, short_b),
            lambda: upstream.levenshtein_distance(short_a, short_b),
            10_000,
        ),
        (
            "Levenshtein, 2,048 chars",
            lambda: mojo.levenshtein_distance(lev_a, lev_b),
            lambda: upstream.levenshtein_distance(lev_a, lev_b),
            3,
        ),
        (
            "Damerau-Levenshtein, 512 chars",
            lambda: mojo.damerau_levenshtein_distance(dam_a, dam_b),
            lambda: upstream.damerau_levenshtein_distance(dam_a, dam_b),
            10,
        ),
        (
            "Jaro-Winkler, 2,000 chars",
            lambda: mojo.jaro_winkler_similarity(jaro_a, jaro_b),
            lambda: upstream.jaro_winkler_similarity(jaro_a, jaro_b),
            10,
        ),
        (
            "Hamming, 1,000,000 chars",
            lambda: mojo.hamming_distance(ham_a, ham_b),
            lambda: upstream.hamming_distance(ham_a, ham_b),
            30,
        ),
        (
            "Jaccard words, 100,000 tokens",
            lambda: mojo.jaccard_similarity(text_a, text_b),
            lambda: upstream.jaccard_similarity(text_a, text_b),
            10,
        ),
        (
            "Soundex, one name",
            lambda: mojo.soundex("Ashcraft"),
            lambda: upstream.soundex("Ashcraft"),
            20_000,
        ),
        (
            "Metaphone, one name",
            lambda: mojo.metaphone("Dunningham"),
            lambda: upstream.metaphone("Dunningham"),
            20_000,
        ),
    ]

    print(f"Machine: {cpu_name()}, {platform.system()} {platform.release()}")
    print(f"Python: {platform.python_version()}, upstream jellyfish: {version('jellyfish')}")
    print()
    print("| case | mojo-jellyfish | jellyfish | upstream / Mojo |")
    print("| --- | ---: | ---: | ---: |")
    for name, ours, theirs, number in cases:
        ours_result = ours()
        theirs_result = theirs()
        if isinstance(ours_result, float):
            assert abs(ours_result - theirs_result) < 1e-12
        else:
            assert ours_result == theirs_result
        ours_time = best_time(ours, number)
        theirs_time = best_time(theirs, number)
        ratio = theirs_time / ours_time
        label = "faster" if ratio >= 1 else "slower"
        print(
            f"| {name} | {format_time(ours_time)} | {format_time(theirs_time)} "
            f"| {ratio:.2f}x {label} |"
        )


if __name__ == "__main__":
    main()
