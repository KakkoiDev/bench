#!/usr/bin/perl
# Two deterministic strategies for the same 0/1 knapsack instance.
use strict; use warnings;
my ($strategy, $capacity, $file) = @ARGV;
open my $fh, '<', $file or die "cannot read $file\n";
my @items;
while (<$fh>) { my ($w, $v) = split; push @items, { w => $w, v => $v } if defined $v; }
close $fh;

my ($weight, $value) = (0, 0);
if ($strategy eq 'greedy') {
  # Highest value-per-weight first: fast, and not always optimal
  for my $it (sort { $b->{v} / $b->{w} <=> $a->{v} / $a->{w} } @items) {
    next if $weight + $it->{w} > $capacity;
    $weight += $it->{w}; $value += $it->{v};
  }
} else {
  # Exact dynamic program: slower, optimal
  my @best = (0) x ($capacity + 1);
  my @wt   = (0) x ($capacity + 1);
  for my $it (@items) {
    for (my $c = $capacity; $c >= $it->{w}; $c--) {
      if ($best[$c - $it->{w}] + $it->{v} > $best[$c]) {
        $best[$c] = $best[$c - $it->{w}] + $it->{v};
        $wt[$c]   = $wt[$c - $it->{w}] + $it->{w};
      }
    }
  }
  $value = $best[$capacity]; $weight = $wt[$capacity];
}
print "value $value\nweight $weight\n";
