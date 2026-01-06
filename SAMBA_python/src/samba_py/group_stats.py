#!/usr/bin/env python3
"""
Group stats utilities for SAMBA_python (samba_py).

Faithful translation of MATLAB compare_group_stats_exec.m

Key behaviors preserved:
- Reads tab-delimited stats table with a header row
- ROI column required; optional structure column supported
- Group runnos passed as comma-delimited strings
- Optional skip_first_row defaults to 1 (skip exterior ROI row)
- If contrast indicates volumes: normalize by "brain total" per specimen and
  append brain total as ROI '0'
- Two-sample t-test (equal variance) per ROI, plus BH FDR correction
- Permutation p-values per ROI (mattest-style) using N permutations
- Writes output with a 2-line header describing groups then a TSV table

HPC/Singularity-friendly: no GUI, no shelling-out required.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import csv
import math

import numpy as np
from scipy import stats


@dataclass(frozen=True)
class CompareGroupStatsConfig:
    stats_file: Path
    contrast: str
    group_1_name: str
    group_2_name: str
    group_1_runno_string: str
    group_2_runno_string: str
    out_dir: Optional[Path] = None
    skip_first_row: bool = True
    n_permute: int = 1000
    alpha: float = 0.05
    permute_seed: Optional[int] = None


def _contrast_is_volume(contrast: str) -> bool:
    c = (contrast or "").strip()
    return c in ("volume", "vol", "volume_mm3_")


def _parse_runnos(runno_string: str) -> List[str]:
    if runno_string is None:
        return []
    parts = [p.strip() for p in runno_string.split(",")]
    return [p for p in parts if p]


def _coerce_skip_first_row(skip_first_row) -> bool:
    """
    MATLAB:
      default: 1
      if char -> str2num
      skip_first_row = ~(skip_first_row==0)

    Python:
      None -> True
      "0" / 0 -> False
      else -> True
    """
    if skip_first_row is None:
        return True
    if isinstance(skip_first_row, str):
        s = skip_first_row.strip()
        try:
            v = int(float(s))
        except Exception:
            v = 1
        return not (v == 0)
    try:
        v = int(skip_first_row)
    except Exception:
        v = 1
    return not (v == 0)


def _resolve_stats_file(stats_file: Path, contrast: str) -> Path:
    if stats_file.exists() and stats_file.is_dir():
        return stats_file / f"studywide_stats_for_{contrast}.txt"
    return stats_file


def _resolve_out_dir(stats_file: Path, out_dir: Optional[Path]) -> Path:
    return stats_file.parent if out_dir is None else out_dir


def _read_stats_tsv(path: Path) -> Tuple[List[str], Dict[str, List[str]]]:
    with path.open("r", newline="") as f:
        reader = csv.reader(f, delimiter="\t")
        try:
            headers = next(reader)
        except StopIteration:
            raise ValueError(f"Empty stats file: {path}")

        headers = [h.strip() for h in headers if h is not None]
        if len(headers) == 0:
            raise ValueError(f"Missing header row in stats file: {path}")

        cols: Dict[str, List[str]] = {h: [] for h in headers}

        for row in reader:
            if len(row) < len(headers):
                row = row + [""] * (len(headers) - len(row))
            for h, v in zip(headers, row[: len(headers)]):
                cols[h].append(v)

    return headers, cols


def _find_column(cols: Dict[str, List[str]], wanted: Sequence[str]) -> Optional[str]:
    """
    Return the actual column name in cols matching any of wanted,
    case-insensitive.
    """
    lower_map = {k.lower(): k for k in cols.keys()}
    for w in wanted:
        k = lower_map.get(w.lower())
        if k is not None:
            return k
    return None


def _as_float_array(values: Sequence[str]) -> np.ndarray:
    out = np.empty(len(values), dtype=np.float64)
    for i, v in enumerate(values):
        s = (v or "").strip()
        if s == "" or s.lower() in ("nan", "na", "null"):
            out[i] = np.nan
        else:
            try:
                out[i] = float(s)
            except Exception:
                out[i] = np.nan
    return out


def _benjamini_hochberg(p: np.ndarray) -> np.ndarray:
    p = np.asarray(p, dtype=np.float64)
    n = p.size
    adj = np.full(n, np.nan, dtype=np.float64)

    mask = np.isfinite(p)
    p_f = p[mask]
    if p_f.size == 0:
        return adj

    order = np.argsort(p_f)
    p_sorted = p_f[order]
    m = p_sorted.size
    ranks = np.arange(1, m + 1, dtype=np.float64)

    q_sorted = p_sorted * (m / ranks)
    q_sorted = np.minimum.accumulate(q_sorted[::-1])[::-1]
    q_sorted = np.clip(q_sorted, 0.0, 1.0)

    q_back = np.empty_like(p_sorted)
    q_back[order] = q_sorted
    adj[mask] = q_back
    return adj


def _ttest2_equalvar_by_row(g2: np.ndarray, g1: np.ndarray, alpha: float) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """
    Per-row two-sample t-test (equal variances, two-sided), NaN-aware.

    Returns:
      h, p, ci_low, ci_high, tstat
    """
    n_labels = g1.shape[0]
    h = np.zeros(n_labels, dtype=np.float64)
    p = np.full(n_labels, np.nan, dtype=np.float64)
    ci_low = np.full(n_labels, np.nan, dtype=np.float64)
    ci_high = np.full(n_labels, np.nan, dtype=np.float64)
    tstat_out = np.full(n_labels, np.nan, dtype=np.float64)

    for i in range(n_labels):
        x = g2[i, :]
        y = g1[i, :]

        x = x[np.isfinite(x)]
        y = y[np.isfinite(y)]
        nx = x.size
        ny = y.size
        if nx < 2 or ny < 2:
            continue

        tstat, pval = stats.ttest_ind(x, y, equal_var=True, alternative="two-sided")
        tstat_out[i] = float(tstat)
        p[i] = float(pval)
        h[i] = 1.0 if (pval <= alpha) else 0.0

        # CI for difference of means (x - y), pooled SD
        mx = float(np.mean(x))
        my = float(np.mean(y))
        vx = float(np.var(x, ddof=1))
        vy = float(np.var(y, ddof=1))
        df = nx + ny - 2
        sp2 = ((nx - 1) * vx + (ny - 1) * vy) / df
        se = math.sqrt(sp2 * (1.0 / nx + 1.0 / ny))
        if not np.isfinite(se) or se == 0.0:
            continue

        tcrit = stats.t.ppf(1.0 - alpha / 2.0, df)
        diff = mx - my
        ci_low[i] = diff - tcrit * se
        ci_high[i] = diff + tcrit * se

    # Match MATLAB: h is NaN where p is NaN
    h[np.isnan(p)] = np.nan
    return h, p, ci_low, ci_high, tstat_out


def _perm_pvals_by_row(g2: np.ndarray, g1: np.ndarray, n_permute: int, seed: Optional[int]) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n_labels = g1.shape[0]
    pperm = np.full(n_labels, np.nan, dtype=np.float64)

    for i in range(n_labels):
        x = g2[i, :]
        y = g1[i, :]
        x = x[np.isfinite(x)]
        y = y[np.isfinite(y)]
        nx, ny = x.size, y.size
        if nx < 1 or ny < 1:
            continue

        obs = float(np.mean(x) - np.mean(y))
        combined = np.concatenate([x, y], axis=0)
        n = combined.size
        if n < 2:
            continue

        count = 0
        for _ in range(int(n_permute)):
            perm = rng.permutation(n)
            x_idx = perm[:nx]
            y_idx = perm[nx:]
            diff = float(np.mean(combined[x_idx]) - np.mean(combined[y_idx]))
            if abs(diff) >= abs(obs):
                count += 1

        pperm[i] = (count + 1.0) / (float(n_permute) + 1.0)

    return pperm


def compare_group_stats(config: CompareGroupStatsConfig) -> Path:
    stats_file = _resolve_stats_file(Path(config.stats_file), config.contrast)
    out_dir = _resolve_out_dir(stats_file, config.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    vols = 1 if _contrast_is_volume(config.contrast) else 0

    g1_runnos = _parse_runnos(config.group_1_runno_string)
    g2_runnos = _parse_runnos(config.group_2_runno_string)
    num_g1 = len(g1_runnos)
    num_g2 = len(g2_runnos)

    out_file = out_dir / f"{config.contrast}_group_stats_{config.group_1_name}_n{num_g1}_vs_{config.group_2_name}_n{num_g2}.txt"

    _, cols = _read_stats_tsv(stats_file)

    roi_col = _find_column(cols, ["ROI", "roi"])
    if roi_col is None:
        raise ValueError(f"Stats file missing required ROI column (ROI/roi): {stats_file}")

    struct_col = _find_column(cols, ["structure", "Structure", "STRUCTURE"])
    include_structure_names = struct_col is not None

    roi_raw = cols[roi_col]
    n_rows = len(roi_raw)

    start = 1 if config.skip_first_row else 0
    if start >= n_rows:
        raise ValueError(f"skip_first_row={config.skip_first_row} leaves no data rows in: {stats_file}")

    ROIs: List[int] = []
    for v in roi_raw[start:]:
        s = (v or "").strip()
        try:
            ROIs.append(int(float(s)))
        except Exception:
            ROIs.append(-1)

    Structures: Optional[List[str]] = None
    if include_structure_names:
        Structures = [(v or "").strip() for v in cols[struct_col][start:]]

    num_labels = n_rows - start

    def get_group_array(runnos: List[str]) -> np.ndarray:
        arr = np.zeros((num_labels, len(runnos)), dtype=np.float64)
        for j, r in enumerate(runnos):
            if r not in cols:
                raise ValueError(f"Missing runno column '{r}' in stats file: {stats_file}")
            col = _as_float_array(cols[r])[start:]
            if col.size != num_labels:
                raise ValueError(f"Column length mismatch for '{r}' (expected {num_labels}, got {col.size})")
            arr[:, j] = col
        return arr

    g1_array = get_group_array(g1_runnos)
    g2_array = get_group_array(g2_runnos)

    # MATLAB recomputes these
    num_g1 = g1_array.shape[1]
    num_g2 = g2_array.shape[1]
    num_labels = g1_array.shape[0]

    if vols == 1:
        g1_ext = 0.0
        g2_ext = 0.0
        if not config.skip_first_row:
            g1_ext = g1_array[0, :]
            g2_ext = g2_array[0, :]

        brain_g1 = np.nansum(g1_array, axis=0) - g1_ext
        brain_g2 = np.nansum(g2_array, axis=0) - g2_ext

        g1_array = 100.0 * g1_array / brain_g1.reshape(1, -1)
        g2_array = 100.0 * g2_array / brain_g2.reshape(1, -1)

        g1_array = np.vstack([g1_array, brain_g1.reshape(1, -1)])
        g2_array = np.vstack([g2_array, brain_g2.reshape(1, -1)])

        ROIs.append(0)
        if include_structure_names and Structures is not None:
            Structures.append("Total Labeled Volume")

        num_labels = g1_array.shape[0]

    mean_g1 = np.nanmean(g1_array, axis=1)
    mean_g2 = np.nanmean(g2_array, axis=1)
    std_g1 = np.nanstd(g1_array, axis=1, ddof=1)
    std_g2 = np.nanstd(g2_array, axis=1, ddof=1)

    h, p, CI_1, CI_2, t_stats = _ttest2_equalvar_by_row(g2_array, g1_array, alpha=config.alpha)
    adj_p = _benjamini_hochberg(p)
    ppermute = _perm_pvals_by_row(g2_array, g1_array, n_permute=config.n_permute, seed=config.permute_seed)

    pooledsd = np.sqrt((num_g1 - 1) * (std_g1 ** 2) + (num_g2 - 1) * (std_g2 ** 2)) / np.sqrt(num_g1 + num_g2 - 2)
    cohen_d = (mean_g2 - mean_g1) / pooledsd
    difference = (mean_g2 - mean_g1) * 100.0 / mean_g1

    # MATLAB CI lines (NOTE: these are mean +/- 1.96*std, not SEM)
    ci_l_g2 = mean_g2 - 1.96 * std_g2
    ci_h_g2 = mean_g2 + 1.96 * std_g2
    ci_l_g1 = mean_g1 - 1.96 * std_g1
    ci_h_g1 = mean_g1 + 1.96 * std_g1

    sem_g2 = std_g2 / math.sqrt(num_g2) if num_g2 > 0 else np.full_like(std_g2, np.nan)
    sem_g1 = std_g1 / math.sqrt(num_g1) if num_g1 > 0 else np.full_like(std_g1, np.nan)

    sig_idx = np.where(np.isfinite(adj_p) & (adj_p < config.alpha))[0]
    if sig_idx.size > 0:
        sig_rois = [ROIs[i] for i in sig_idx.tolist()]
        print("\nLabels featuring uncorrected significant differences:")
        line: List[str] = []
        for k, roi in enumerate(sig_rois, start=1):
            line.append(str(roi))
            if (k % 15 == 0) or (k == len(sig_rois)):
                print(", ".join(line))
                line = []
        print("")

    # Build output columns (match MATLAB ordering/semantics)
    base_cols: Dict[str, object] = {
        "ROI": np.asarray(ROIs, dtype=np.int64),

        f"mean_{config.group_2_name}": mean_g2,
        f"mean_{config.group_1_name}": mean_g1,
        f"std_{config.group_2_name}": std_g2,
        f"std_{config.group_1_name}": std_g1,
        f"sem_{config.group_2_name}": sem_g2,
        f"sem_{config.group_1_name}": sem_g1,

        # IMPORTANT: MATLAB writes these values in THIS order:
        # ci_l_g2; ci_l_g1; ci_h_g1; ci_h_g2
        f"ci1_{config.group_2_name}": ci_l_g2,
        f"ci2_{config.group_2_name}": ci_l_g1,
        f"ci1_{config.group_1_name}": ci_h_g1,
        f"ci2_{config.group_1_name}": ci_h_g2,

        "hypothesis": h,
        "p_value": p,
        "ppermute": ppermute,
        "P_FDR_0p05_BH": adj_p,

        "CI_1": CI_1,
        "CI_2": CI_2,
        "t_stats": t_stats,
        "cohen_d": cohen_d,
        "difference": difference,
    }

    if include_structure_names and Structures is not None:
        myheader = [
            "ROI", "structure",
            f"mean_{config.group_2_name}", f"mean_{config.group_1_name}",
            f"std_{config.group_2_name}", f"std_{config.group_1_name}",
            f"sem_{config.group_2_name}", f"sem_{config.group_1_name}",
            f"ci1_{config.group_2_name}", f"ci2_{config.group_2_name}",
            f"ci1_{config.group_1_name}", f"ci2_{config.group_1_name}",
            "hypothesis", "p_value", "ppermute", "P_FDR_0p05_BH",
            "CI_1", "CI_2", "t_stats", "cohen_d", "difference",
        ]
    else:
        myheader = [
            "ROI",
            f"mean_{config.group_2_name}", f"mean_{config.group_1_name}",
            f"std_{config.group_2_name}", f"std_{config.group_1_name}",
            f"sem_{config.group_2_name}", f"sem_{config.group_1_name}",
            f"ci1_{config.group_2_name}", f"ci2_{config.group_2_name}",
            f"ci1_{config.group_1_name}", f"ci2_{config.group_1_name}",
            "hypothesis", "p_value", "ppermute", "P_FDR_0p05_BH",
            "CI_1", "CI_2", "t_stats", "cohen_d", "difference",
        ]

    print(f"Comparing {config.contrast} of groups: {config.group_1_name} (n = {num_g1}) vs. {config.group_2_name} (n = {num_g2}) for {num_labels} labels...")

    with out_file.open("w", newline="") as f:
        f.write(f"{config.group_1_name}(n={num_g1}):{config.group_1_runno_string}\n")
        f.write(f"{config.group_2_name}(n={num_g2}):{config.group_2_runno_string}\n")

        writer = csv.writer(f, delimiter="\t", lineterminator="\n")
        writer.writerow(myheader)

        for i in range(num_labels):
            row: List[str] = []
            for colname in myheader:
                if colname == "structure":
                    row.append(Structures[i] if Structures is not None else "")
                    continue

                v = base_cols[colname][i]  # type: ignore[index]
                if isinstance(v, (np.floating, float)):
                    row.append("NaN" if np.isnan(v) else f"{float(v):.10g}")
                elif isinstance(v, (np.integer, int)):
                    row.append(str(int(v)))
                else:
                    row.append(str(v))
            writer.writerow(row)

    print(f"\nWriting table to file:\n{out_file}\n")
    return out_file
