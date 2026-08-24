# mojo-jellyfish

`mojo-jellyfish` is a standalone Mojo port of the public API in
[`jellyfish`](https://github.com/jamesturk/jellyfish), the Python package for
approximate and phonetic string matching. The dynamic-programming and scanning
kernels run in a compiled Mojo shared library; a small Python layer preserves
upstream names, signatures, Unicode behavior, and exceptions.

The import name is `mojo_jellyfish`. For the covered API, changing
`import jellyfish as jf` to `import mojo_jellyfish as jf` is the only code
change required.

## Coverage

The complete public function surface of upstream jellyfish 1.2.1 is covered:

- Distances: `levenshtein_distance`, `damerau_levenshtein_distance`, and
  `hamming_distance`
- Similarities: `jaro_similarity`, `jaro_winkler_similarity`, and
  `jaccard_similarity`
- Phonetic encoders: `soundex`, `metaphone`, `nysiis`, and
  `match_rating_codex`
- Phonetic comparison: `match_rating_comparison`
- `long_tolerance` in `jaro_winkler_similarity`
- Unicode extended grapheme-cluster semantics for the five compiled comparison
  kernels

The Mojo library contains Levenshtein, true unrestricted
Damerau-Levenshtein, Hamming, Jaro/Jaro-Winkler, ASCII word Jaccard, Soundex,
Metaphone, NYSIIS, and Match Rating Codex. Unicode and n-gram Jaccard plus the
final Match Rating comparison remain in Python.

Not covered are upstream's private implementation modules (`_rustyfish` and
`_jellyfish`) and removed pre-1.0 aliases such as `jaro_distance`. There are no
classes or other public objects in the current upstream API.

## Install and build

The Pixi environment pins the tested Mojo nightly and installs the real
upstream package for differential tests:

```bash
pixi install
pixi run build
pixi run test
```

`pixi run build` compiles the single Mojo compilation unit into
`dist/libmojo-jellyfish.so`.

## Usage

```python
import mojo_jellyfish as jellyfish

assert jellyfish.levenshtein_distance("jellyfish", "smellyfish") == 2
assert jellyfish.damerau_levenshtein_distance("jellyfish", "jellyfihs") == 1
assert jellyfish.jaro_similarity("jellyfish", "smellyfish") > 0.89

assert jellyfish.soundex("Jellyfish") == "J412"
assert jellyfish.metaphone("Jellyfish") == "JLFX"
assert jellyfish.nysiis("Jellyfish") == "JALYF"
assert jellyfish.match_rating_codex("Jellyfish") == "JLYFSH"
```

From the checkout, Pixi adds `python/` to `PYTHONPATH`, so the example can be
run with `pixi run python example.py`.

## Correctness

The test suite compares every public function with the installed Rust-backed
`jellyfish` package. It includes published vectors, 500 deterministic random
cases, type and error behavior, empty inputs, true Damerau transpositions,
both Jaro-Winkler modes, accented names, combining sequences, flags, Indic
clusters, and multi-code-point emoji. On the pinned environment:

```text
121 passed in 0.80s
```

## Benchmarks

Measured with `pixi run bench`, which takes a machine-wide file lock. Times are
best-of-three per-call timings after one warm-up. The comparison is against
upstream jellyfish 1.2.1, whose default Python extension is written in Rust.
A ratio below 1 means Mojo is slower.

Machine: Intel Xeon E5-2697 v4 at 2.30 GHz, Linux 6.8.0-136-generic,
Python 3.13.14.

| case | mojo-jellyfish | jellyfish | upstream / Mojo |
| --- | ---: | ---: | ---: |
| Levenshtein, 10-char names | 1.8 us | 2.3 us | 1.22x faster |
| Levenshtein, 2,048 chars | 5.96 ms | 33.40 ms | 5.60x faster |
| Damerau-Levenshtein, 512 chars | 1.31 ms | 6.80 ms | 5.17x faster |
| Jaro-Winkler, 2,000 chars | 1.02 ms | 1.64 ms | 1.61x faster |
| Hamming, 1,000,000 chars | 1.30 ms | 109.10 ms | 83.72x faster |
| Jaccard words, 100,000 tokens | 4.87 ms | 21.62 ms | 4.44x faster |
| Soundex, one name | 136.7 ns | 391.6 ns | 2.87x faster |
| Metaphone, one name | 238.4 ns | 463.3 ns | 1.94x faster |

Short ASCII Levenshtein now uses byte inputs, stack scratch, and SIMD
prefix/suffix trimming. ASCII word Jaccard builds two exact open-addressed
token sets and falls back to Python if its bounded scratch table fills. A thin
CPython ABI bridge passes compact ASCII string storage directly to Mojo without
copying. Mojo folds ASCII case during the scan and returns packed phonetic
results, avoiding both temporary encoded strings and `ctypes` call overhead.

There is no GPU path. These kernels either move substantially more data than
arithmetic they perform or depend on sequential dynamic-programming state,
branches, and irregular hash-table probes. Transfer and launch overhead would
dominate rather than accelerate them.

These are the actual results from this checkout, not projections. Run
`pixi run bench` to measure the current machine.

## How it works

Python strings do not cross the C ABI. The wrapper validates arguments and
passes compact ASCII byte buffers directly for the short-distance, word
Jaccard, and phonetic fast paths. Other ASCII comparison inputs use zero-copy
NumPy views over encoded `uint32` buffers. Non-ASCII comparison inputs are
segmented into extended grapheme clusters and densely numbered, matching
upstream's character semantics for composed emoji and combining marks.
Phonetic input is uppercased and, where required by the algorithm, NFKD
normalized before entering Mojo.

All buffers are caller-owned, contiguous NumPy arrays. Their addresses cross
the ABI as 64-bit integers and the exported, non-parametric Mojo functions
reconstruct fixed-origin pointers. Results are returned as integers/floats or
written into caller-owned output buffers. Short ASCII Levenshtein keeps its
row on the stack; longer Levenshtein uses one caller-owned `int64` row. True
Damerau-Levenshtein uses a flat score matrix and last-seen table; Jaro uses two
byte flag arrays; ASCII word Jaccard uses bounded caller-owned hash tables. The
shared library allocates no heap memory and exposes no Mojo objects to Python.

MIT licensed.
