#!/usr/bin/env bash
set -euo pipefail

# Patch SAMBA_pipeline_utilities.pm write_array_to_file to use sysopen/syswrite
# and remove the -T filehandle check (can misbehave and is not meaningful here).

FILE="SAMBA_pipeline_utilities.pm"

if [[ ! -f "$FILE" ]]; then
  echo "FATAL: must be run from the SAMBA repo root (missing $FILE)" >&2
  exit 1
fi

# Backup (tracked changes still show via git diff)
cp -f "$FILE" "${FILE}.bak.$(date +%Y%m%d_%H%M%S)"

perl -0777 -i -pe '
  my $orig = $_;

  # Find the sub write_array_to_file block (conservatively)
  if ($orig !~ /sub\s+write_array_to_file\s*\{.*?\n\}/s) {
    die "FATAL: could not locate sub write_array_to_file in SAMBA_pipeline_utilities.pm\n";
  }

  $orig =~ s{
    sub\s+write_array_to_file\s*\{
    .*?
    \n\}
  }{
sub write_array_to_file {
    use strict;
    use warnings;
    use Carp qw(croak);
    use Fcntl qw(:DEFAULT);

    my ($file, $array_ref, @rest) = @_;

    # Basic sanity checks
    if (!defined $file || $file eq q{}) {
        croak "write_array_to_file: undefined or empty filename";
    }
    if (!defined $array_ref || ref($array_ref) ne q{ARRAY}) {
        croak "write_array_to_file: second argument must be an array reference";
    }

    # Ensure parent directory exists (helps produce a clearer error early)
    if ($file =~ m{^(.*)/[^/]+$}) {
        my $dir = $1;
        if (defined $dir && $dir ne q{} && !-d $dir) {
            croak "write_array_to_file: parent directory does not exist: $dir";
        }
    }

    # Open with sysopen to avoid PerlIO layer surprises
    sysopen(my $fh, $file, O_CREAT|O_TRUNC|O_WRONLY)
        or croak "write_array_to_file: could not sysopen $file: $!";

    # Write each line using syswrite; force newline behavior exactly as provided
    foreach my $line (@{$array_ref}) {
        $line = q{} unless defined $line;
        my $len = length($line);
        my $off = 0;
        while ($off < $len) {
            my $n = syswrite($fh, $line, $len - $off, $off);
            defined $n or croak "write_array_to_file: ERROR on syswrite to $file: $!";
            $n > 0 or croak "write_array_to_file: ERROR on syswrite to $file: wrote 0 bytes";
            $off += $n;
        }
    }

    close($fh) or croak "write_array_to_file: ERROR closing $file: $!";

    return 1;
}
}sx or die "FATAL: failed to replace write_array_to_file block\n";

  $_ = $orig;
' "$FILE"

echo "[OK] Patched $FILE"
echo "[NEXT] Review diff:"
echo "  git diff -- $FILE"
