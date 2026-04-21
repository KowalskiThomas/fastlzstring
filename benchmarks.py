"""
Benchmarks comparing lzstr (this package) vs lzstring (PyPI) for
compress/decompress operations across different data sizes and types.

Run with:
    python benchmarks.py
    python benchmarks.py --worker  # single worker pass (used internally by pyperf)
"""

import pyperf
import lzstring as _lzstring
from lzstr import LZStringCompressor, LZStringDecompressor

# ---------------------------------------------------------------------------
# Benchmark data
# ---------------------------------------------------------------------------

_SHORT_TEXT = "Hello, World! This is a short test string."
_MEDIUM_TEXT = _SHORT_TEXT * 25  # ~1 KB
_LARGE_TEXT = _SHORT_TEXT * 600  # ~25 KB
_REPETITIVE_TEXT = "aaabbbccc" * 1000  # highly compressible
_RANDOM_TEXT = "".join(chr((i * 6364136223846793005 + 1442695040888963407) & 0x7F) for i in range(500))

_DATASETS: list[tuple[str, str, bytes]] = [
    ("short",       _SHORT_TEXT,       _SHORT_TEXT.encode()),
    ("medium",      _MEDIUM_TEXT,      _MEDIUM_TEXT.encode()),
    ("large",       _LARGE_TEXT,       _LARGE_TEXT.encode()),
    ("repetitive",  _REPETITIVE_TEXT,  _REPETITIVE_TEXT.encode()),
    ("random",      _RANDOM_TEXT,      _RANDOM_TEXT.encode()),
]

# Pre-compressed payloads for decompression benchmarks
_lzstring_obj = _lzstring.LZString()
_PRECOMPRESSED: dict[str, tuple[str, str]] = {
    label: (
        _lzstring_obj.compressToBase64(text),
        LZStringCompressor.compress_to_base64(data_bytes),
    )
    for label, text, data_bytes in _DATASETS
}

# ---------------------------------------------------------------------------
# Benchmark functions
# ---------------------------------------------------------------------------

def bench_lzstring_compress_base64(loops: int, text: str) -> float:
    obj = _lzstring.LZString()
    t0 = pyperf.perf_counter()
    for _ in range(loops):
        obj.compressToBase64(text)
    return pyperf.perf_counter() - t0


def bench_lzstr_compress_base64(loops: int, data: bytes) -> float:
    t0 = pyperf.perf_counter()
    for _ in range(loops):
        LZStringCompressor.compress_to_base64(data)
    return pyperf.perf_counter() - t0


def bench_lzstring_decompress_base64(loops: int, compressed: str) -> float:
    obj = _lzstring.LZString()
    t0 = pyperf.perf_counter()
    for _ in range(loops):
        obj.decompressFromBase64(compressed)
    return pyperf.perf_counter() - t0


def bench_lzstr_decompress_base64(loops: int, compressed: str) -> float:
    t0 = pyperf.perf_counter()
    for _ in range(loops):
        LZStringDecompressor.decompress_from_base64(compressed)
    return pyperf.perf_counter() - t0


def bench_lzstring_compress_bytes(loops: int, text: str) -> float:
    obj = _lzstring.LZString()
    t0 = pyperf.perf_counter()
    for _ in range(loops):
        obj.compress(text)
    return pyperf.perf_counter() - t0


def bench_lzstr_compress_bytes(loops: int, data: bytes) -> float:
    t0 = pyperf.perf_counter()
    for _ in range(loops):
        LZStringCompressor.compress_to_bytes(data)
    return pyperf.perf_counter() - t0


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def main() -> None:
    runner = pyperf.Runner()

    for label, text, data_bytes in _DATASETS:
        lzstring_compressed, lzstr_compressed = _PRECOMPRESSED[label]

        runner.bench_time_func(
            f"lzstring.compressToBase64 [{label}]",
            bench_lzstring_compress_base64,
            text,
        )
        runner.bench_time_func(
            f"lzstr.compress_to_base64 [{label}]",
            bench_lzstr_compress_base64,
            data_bytes,
        )
        runner.bench_time_func(
            f"lzstring.decompressFromBase64 [{label}]",
            bench_lzstring_decompress_base64,
            lzstring_compressed,
        )
        runner.bench_time_func(
            f"lzstr.decompress_from_base64 [{label}]",
            bench_lzstr_decompress_base64,
            lzstr_compressed,
        )
        runner.bench_time_func(
            f"lzstring.compress (raw) [{label}]",
            bench_lzstring_compress_bytes,
            text,
        )
        runner.bench_time_func(
            f"lzstr.compress_to_bytes [{label}]",
            bench_lzstr_compress_bytes,
            data_bytes,
        )


if __name__ == "__main__":
    main()
