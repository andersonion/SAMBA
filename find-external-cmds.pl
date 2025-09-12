#!/usr/bin/env perl
use strict;
use warnings;
use File::Find;

my @files;
find({ no_chdir=>1, wanted=>sub{
    return unless -f $_ && $_ =~ /\.(pl|pm)\z/;
    push @files, $File::Find::name;
}}, @ARGV ? @ARGV : ('.'));

for my $f (@files) {
    open my $fh, '<:raw', $f or do { warn "open $f: $!"; next };
    local $/; my $src = <$fh>; close $fh;

    # Strip POD (=pod..=cut, =head1..=cut, etc.)
    $src =~ s/^\s*=(?:pod|head\d|over|item|begin|for|encoding)\b.*?^=cut\s*$//gms;

    my @lines = split /\n/, $src;
    for my $i (0..$#lines) {
        my $line = $lines[$i];

        # remove trailing # comments that are not inside quotes (simple heuristic)
        my $code = $line;
        my $quoted = 0;
        my $esc = 0;
        my $clean = '';
        for my $ch (split //, $code) {
            if (!$quoted && $ch eq '#') { last }          # start of comment
            $clean .= $ch;
            if ($esc) { $esc = 0; next }
            if ($ch eq '\\') { $esc = 1; next }
            $quoted = !$quoted if $ch eq '"';
        }
        $code = $clean;

        # match common external-run patterns
        if ($code =~ /
             (?:\bsystem\s*\()|
             (?:\bexec\b(?!\s*=>))|
             (?:\bqx\s*[\(\{\[\<\/'"])|
             (?:`[^`]*`)|
             (?:\bopen3\s*\()|
             (?:\bIPC::Run::\w+)|
             (?:\bopen\s*\([^,]*,\s*['"]?\|)|
             (?:\|\-\s*[,\)])|
             (?:\-\|\s*[,\)])
            /x) {
            print "$f:", $i+1, ":", $line, "\n";
        }
    }
}
