"""Load the Mojo shared library and declare its C ABI."""

from __future__ import annotations

import ctypes
import os
import subprocess
import sysconfig

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIB = os.environ.get("MOJO_JELLYFISH_LIB") or os.path.join(
    ROOT, "dist", "libmojo-jellyfish.so"
)
NATIVE = os.path.join(
    ROOT,
    "python",
    "mojo_jellyfish",
    "_native" + sysconfig.get_config_var("EXT_SUFFIX"),
)

I = ctypes.c_int64
F = ctypes.c_double
P = ctypes.c_void_p
S = ctypes.c_char_p
U32 = ctypes.c_uint32
U64 = ctypes.c_uint64

_SIGNATURES = {
    "mj_levenshtein": ([I, I, I, I, I], I),
    "mj_levenshtein_ascii_short": ([S, S, I, I], I),
    "mj_hamming": ([I, I, I, I], I),
    "mj_damerau": ([I, I, I, I, I, I, I], I),
    "mj_jaro": ([I, I, I, I, I, I, I], F),
    "mj_jaccard_ascii_words": ([S, S, I, I, I, I, I, I, I], F),
    "mj_soundex": ([I, I, I], I),
    "mj_soundex_ascii_packed": ([S, I], U32),
    "mj_metaphone": ([I, I, I], I),
    "mj_metaphone_ascii": ([S, I, P], I),
    "mj_metaphone_ascii_packed": ([S, I], U64),
    "mj_nysiis": ([I, I, I], I),
    "mj_match_rating_codex": ([I, I, I], I),
}


class BuildError(RuntimeError):
    pass


def build(force: bool = False) -> str:
    source = os.path.join(ROOT, "src", "kernels.mojo")
    native_source = os.path.join(ROOT, "python", "mojo_jellyfish", "_native.c")
    oldest_output = min(
        os.path.getmtime(path) if os.path.exists(path) else 0 for path in (LIB, NATIVE)
    )
    newest_source = max(os.path.getmtime(source), os.path.getmtime(native_source))
    if not force and oldest_output >= newest_source:
        return LIB
    script = os.path.join(ROOT, "build", "build.sh")
    proc = subprocess.run(
        ["bash", script], cwd=ROOT, capture_output=True, text=True, timeout=1800
    )
    if proc.returncode != 0 or not os.path.exists(LIB) or not os.path.exists(NATIVE):
        raise BuildError((proc.stderr or proc.stdout).strip()[:8000])
    return LIB


_library: ctypes.CDLL | None = None


def lib() -> ctypes.CDLL:
    global _library
    if _library is None:
        _library = ctypes.CDLL(build())
        for name, (argtypes, restype) in _SIGNATURES.items():
            fn = getattr(_library, name)
            fn.argtypes = argtypes
            fn.restype = restype
    return _library


def addr(array) -> int:
    if array.flags.writeable and array.nbytes:
        return ctypes.addressof(ctypes.c_char.from_buffer(array))
    return int(array.__array_interface__["data"][0])
