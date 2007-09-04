#!/usr/bin/perl

use warnings;
use strict;

use Clone::Closure qw/clone/;

use Test::More;

my $tests;

sub rv ($) { $_[0]->() }

my $x = {};
my $y = sub { \$x };
my $z = clone $y;

BEGIN { $tests += 1 }
is rv $y, rv $z, 'lexical from file scope is copied';

my $fb;
{
    my $x = {};
    $fb = sub { \$x };
}
my $fc = clone $fb;

BEGIN { $tests += 1 }
is rv $fb, rv $fc, 'lexical from block-in-file is copied';

my $ef = {};
my $efc = eval q{ sub { \$ef } };
my $efd = clone $efc;

BEGIN { $tests += 1 }
TODO: {
    $] >= 5.008 or local $TODO = q/lexicals in evals don't work under 5.6/;
    is rv $efc, rv $efd, 'lexical from file scope in eval-string is copied';
}

my $eef = {};
my $eefc = eval q{ my $x = {}; sub { \$x } };
my $eefd = clone $eefc;

BEGIN { $tests += 1 }
is rv $eefc, rv $eefd, 'lexical from eval-in-file is copied';

sub clos {
    my $c = {};
    return sub { \$c };
}

my $c = clos;
my $d = clone $c;

BEGIN { $tests += 1 }
isnt rv $c, rv $d, 'lexical from sub scope is cloned';

my @l;
for my $l (1..10) {
    push @l, sub { \$l };
}
my $m = clone $l[0];

BEGIN { $tests += 1 }

TODO: {
    local $TODO = 'loops not detected yet';
    isnt rv $l[0], rv $m, 'lexical from for loop is cloned';
}

my $e = eval q{
    my $e = 1;
    sub { \$e };
};
my $f = clone $e;

BEGIN { $tests += 1 }
is rv $e, rv $f, 'lexical from eval is copied';

sub bc {
    {
        my $bc = {};
        return sub { \$bc };
    }
}
my $bc = bc;
my $bd = clone $bc;

BEGIN { $tests += 1 }
isnt rv $bc, rv $bd, 'lexical from block-in-sub is cloned';

sub lpc {
    my @lc;
    for my $lc (1..10) {
        push @lc, sub { \$lc };
    }
    return $lc[0];
}
my $lc = lpc;
my $ld = clone $lc;

BEGIN { $tests += 1 }
isnt rv $lc, rv $ld, 'lexical from for-in-sub is cloned';

sub ec {
    my $ec = 1;
    return eval q{ sub { \$ec } };
}
my $ec = ec;
my $ed = clone $ec;

BEGIN { $tests += 1 }
TODO: {
    $] >= 5.008 or local $TODO = q/lexicals in evals don't work under 5.6/;
    isnt rv $ec, rv $ed, 'lexical from sub in eval-string is cloned';
}

sub eec {
    return eval q{ my $eec; sub { \$eec } };
}
my $eec = eec;
my $eed = clone $eec;

BEGIN { $tests += 1 }
isnt rv $eec, rv $eed, 'lexical from eval-in-sub is cloned';

sub ac {
    my $x;
    my $y = \$x;
    return sub { \$x }, sub { $y };
}

my $ac = [ ac ];
my $ad = clone $ac;

BEGIN { $tests += 3 }
is   rv $ac->[0], rv $ac->[1], 'sanity check';
isnt rv $ac->[0], rv $ad->[0], 'lexical in closure in array is cloned';
is   rv $ad->[0], rv $ad->[1], 'co-cloned subs share lexicals';

my $gone = 0;

BEGIN {
    package t::Gone;

    sub new { return bless [], $_[0]; }

    sub DESTROY { $gone++; }
}

BEGIN { $tests += 2 }

{
    my $x = t::Gone->new;
    my $leak = sub { $x };
    my $leal = clone $leak;

    ok !$gone, 'sanity check';
}

ok $gone == 1, 'copied lexical is destroyed';

BEGIN { $tests += 3 }

$gone = 0;

sub leam {
    my $x = t::Gone->new;
    return sub { $x };
}

{
    my $leam = leam;
    my $lean = clone $leam;

    ok !$gone, 'sanity check';
}

ok $gone,       'cloned lexical is destroyed';
ok $gone == 2,  'both copies are destroyed';

BEGIN { plan tests => $tests }
