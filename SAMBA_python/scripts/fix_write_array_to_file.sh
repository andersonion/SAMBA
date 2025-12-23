#!/usr/bin/env bash
set -euo pipefail

# Fix write_array_to_file() in SAMBA_pipeline_utilities.pm:
# - remove unreliable -T filehandle check
# - force :raw binmode to avoid PerlIO/text-layer weirdness
# - normalize undefined lines + ensure newline termination

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

f="SAMBA_pipeline_utilities.pm"
if [[ ! -f "$f" ]]; then
  echo "FATAL: $f not found at repo root: $repo_root" >&2
  exit 1
fi

python3 - <<'PY'
from __future__ import annotations
import pathlib
import sys

path = pathlib.Path("SAMBA_pipeline_utilities.pm")
txt = path.read_text(encoding="utf-8", errors="strict")

old = r'''    # Open file for writing using a lexical filehandle
    open my $text_fid, '>', $file
      or croak "write_array_to_file: could not open $file, $!";

    # Optional sanity check: ensure it's treated as text
    croak "write_array_to_file: file <$file> not Text\n"
      unless -T $text_fid;

    # Write each line explicitly to this filehandle
    foreach my $line (@{$array_ref}) {
        print {$text_fid} $line
          or croak "write_array_to_file: ERROR on write to $file: $!";
    }

    close $text_fid
      or croak "write_array_to_file: ERROR closing $file: $!";'''

new = r'''    # Open file for writing using a lexical filehandle
    open my $text_fid, '>', $file
      or croak "write_array_to_file: could not open $file, $!";

    # IMPORTANT:
    #   - Do NOT use -T (text filetest) on a filehandle here; it can be unreliable
    #     on some filesystems / PerlIO stacks and isn't necessary for correctness.
    #   - Force raw mode to avoid PerlIO text-layer weirdness.
    binmode($text_fid, ':raw');

    # Write each line explicitly to this filehandle
    foreach my $line (@{$array_ref}) {
        $line = "" if !defined $line;
        # Ensure newline termination (this is a text-ish file)
        $line .= "\n" if $line !~ /\n\z/;

        print {$text_fid} $line
          or croak "write_array_to_file: ERROR on write to $file: $!";
    }

    close $text_fid
      or croak "write_array_to_file: ERROR closing $file: $!";'''

if old not in txt:
    # Give a helpful clue for mismatch
    import re
    m = re.search(r"open my \$text_fid, '>', \$file.*?close \$text_fid.*?;\n", txt, flags=re.S)
    print("FATAL: Could not find the exact expected block to replace.", file=sys.stderr)
    if m:
        snippet = m.group(0)
        print("\nFound similar block candidate:\n---\n" + snippet[:1200] + ("\n...\n" if len(snippet) > 1200 else "\n---\n"), file=sys.stderr)
    else:
        print("No similar open/close block found.", file=sys.stderr)
    sys.exit(2)

txt2 = txt.replace(old, new, 1)
path.write_text(txt2, encoding="utf-8")
print("OK: updated SAMBA_pipeline_utilities.pm")
PY

echo
echo "=== git diff (target file) ==="
git --no-pager diff -- "$f" || true
echo
echo "Done. If diff looks good:"
echo "  git add $f scripts/fix_write_array_to_file.sh"
echo "  git commit -m \"Harden write_array_to_file: remove -T handle check, force :raw, ensure newline\""
