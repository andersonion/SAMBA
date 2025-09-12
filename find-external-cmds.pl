#!/usr/bin/env perl
use strict;
use warnings;
use File::Find;
use PPI;

my @files;
find(
    { wanted => sub {
        return unless -f $_ && $_ =~ /\.(?:pl|pm)\z/;
        push @files, $File::Find::name;
    }, no_chdir => 1 },
    @ARGV ? @ARGV : ('.')
);

for my $file (@files) {
    my $doc = PPI::Document->new($file) or next;

    # Remove comments & POD nodes
    $_->delete for $doc->find('PPI::Token::Comment')     || ();
    $_->delete for $doc->find('PPI::Token::Pod')         || ();

    my $found;

    # 1) system(...)
    if (my $calls = $doc->find('PPI::Token::Word')) {
        for my $w (@$calls) {
            next unless $w->content eq 'system' || $w->content eq 'exec';
            my $parent = $w->parent or next;
            # Try to get a line number
            my $line = $w->location ? $w->location->[0] : '?';
            print "$file:$line:$w\n";
            $found = 1;
        }
    }

    # 2) backticks and qx//
    if (my $ticks = $doc->find('PPI::Token::QuoteLike::Backtick')) {
        for my $t (@$ticks) {
            my $line = $t->location ? $t->location->[0] : '?';
            print "$file:$line:BACKTICK $t\n";
            $found = 1;
        }
    }
    if (my $qxl = $doc->find('PPI::Token::QuoteLike::Command')) { # qx//
        for my $t (@$qxl) {
            my $line = $t->location ? $t->location->[0] : '?';
            print "$file:$line:QX $t\n";
            $found = 1;
        }
    }

    # 3) open3(...) and IPC::Run
    if (my $words = $doc->find('PPI::Token::Word')) {
        for my $w (@$words) {
            my $txt = $w->content;
            next unless $txt eq 'open3'
                     || $txt =~ /\A(?:IPC::Run::\w+|run|spawn|harness)\z/;
            my $pkg = $w->snext_sibling;
            # Heuristic: only flag IPC::Run forms or run/spawn likely imported
            my $line = $w->location ? $w->location->[0] : '?';
            print "$file:$line:$txt\n";
            $found = 1;
        }
    }

    # 4) open with pipes: open FH, "|cmd" / "cmd|"
    if (my $subs = $doc->find('PPI::Statement::Sub')) {
        # no-op; presence suppresses an unused var warning in some perls
    }
    if (my $opencalls = $doc->find('PPI::Statement')) {
        for my $st (@$opencalls) {
            next unless $st->content =~ /\bopen\s*\(/;
            # Quick token scan for a quoted second arg starting/ending with |
            if ($st->content =~ /open\s*\([^,]+,\s*(['"])\|/s
             || $st->content =~ /open\s*\([^,]+,\s*\|\1/s
             || $st->content =~ /\|\-\s*[,\)]/
             || $st->content =~ /\-\|\s*[,\)]/) {
                my $line = $st->location ? $st->location->[0] : '?';
                (my $preview = $st->content) =~ s/\s+/ /g;
                $preview = substr($preview,0,120) . '...' if length($preview) > 120;
                print "$file:$line:OPEN_PIPE $preview\n";
                $found = 1;
            }
        }
    }
}