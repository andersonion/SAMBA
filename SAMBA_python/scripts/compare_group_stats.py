#!/usr/bin/env python3
"""
CLI entry for MATLAB compare_group_stats_exec.m translation.

Usage (mirrors exec signature order):
  compare_group_stats.py stats_file contrast group_1_name group_2_name g1_runnos g2_runnos [--out-dir DIR] [--skip-first-row 0|1]

- stats_file can be a file OR a directory:
    if directory, we load: <dir>/studywide_stats_for_<contrast>.txt
- out_dir optional: defaults to stats_file directory
- skip_first_row default 1; pass 0 to include the first ROI row
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from samba_py.group_stats import CompareGroupStatsConfig, compare_group_stats, _coerce_skip_first_row


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description="Compare group stats (SAMBA translation of compare_group_stats_exec.m).")
    p.add_argument("stats_file", help="Path to studywide stats TSV file or directory containing it.")
    p.add_argument("contrast", help="Contrast name (also used if stats_file is a directory).")
    p.add_argument("group_1_name", help="Label/name for group 1.")
    p.add_argument("group_2_name", help="Label/name for group 2.")
    p.add_argument("group_1_runno_string", help="Comma-delimited runnos for group 1.")
    p.add_argument("group_2_runno_string", help="Comma-delimited runnos for group 2.")
    p.add_argument("--out-dir", default=None, help="Output directory (defaults to stats_file directory).")
    p.add_argument("--skip-first-row", default="1", help="1 to skip first ROI row (default), 0 to include it.")
    p.add_argument("--n-permute", type=int, default=1000, help="Number of permutations (default 1000).")
    p.add_argument("--alpha", type=float, default=0.05, help="Alpha for hypothesis/FDR threshold (default 0.05).")
    p.add_argument("--permute-seed", type=int, default=None, help="Optional RNG seed for permutation test reproducibility.")

    args = p.parse_args(argv)

    cfg = CompareGroupStatsConfig(
        stats_file=Path(args.stats_file),
        contrast=args.contrast,
        group_1_name=args.group_1_name,
        group_2_name=args.group_2_name,
        group_1_runno_string=args.group_1_runno_string,
        group_2_runno_string=args.group_2_runno_string,
        out_dir=Path(args.out_dir) if args.out_dir else None,
        skip_first_row=_coerce_skip_first_row(args.skip_first_row),
        n_permute=args.n_permute,
        alpha=args.alpha,
        permute_seed=args.permute_seed,
    )

    try:
        compare_group_stats(cfg)
    except Exception as e:
        print(f"[compare_group_stats] ERROR: {e}", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
