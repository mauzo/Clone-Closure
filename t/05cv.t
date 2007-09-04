#!/usr/bin/perl

use warnings;
use strict;

use Test::More;
use B;
use Clone::Closure qw/clone/;

BEGIN { *b = \&B::svref_2object }

my $tests;

{
    BEGIN { $tests += 1 }

    my $x;
    my $sub = sub { \$x };
    my $cv  = clone $sub;

    is  $cv->(), $sub->(), 'lexical from file scope is copied';
}

{
    BEGIN { $tests += 1 }

    my $sub;
    {
        my $x;
        $sub = sub { \$x };
    }
    my $cv = clone $sub;

    is  $cv->(), $sub->(), 'lexical from block-in-file is copied';
}

TODO: {
    $] >= 5.008 or local $TODO = q/lexicals in evals don't work under 5.6/;

    BEGIN { $tests += 1 }

    my $x;
    my $sub = eval q{ sub { \$x } };
    my $cv  = clone $sub;

    is $cv->(), $sub->(), 'lexical from file scope in eval-string is copied';
}

{
    BEGIN { $tests += 1 }

    my $sub = eval q{ my $x = {}; sub { \$x } };
    my $cv  = clone $sub;

    is $cv->(), $sub->(), 'lexical from eval-in-file is copied';
}

{
    BEGIN { $tests += 1 }

    sub clos {
        my $c;
        return sub { \$c };
    }

    my $sub = clos;
    my $cv  = clone $sub;

    isnt $cv->(), $sub->(), 'lexical from sub scope is cloned';
}

TODO: {
    local $TODO = 'loops not detected yet';

    BEGIN { $tests += 1 }

    my @sub;
    for my $l (1..2) {
        push @sub, sub { \$l };
    }
    my $cv = clone $sub[0];

    isnt $cv->(), $sub[0](), 'lexical from for loop is cloned';
}

{
    BEGIN { $tests += 1 }

    my $sub = eval q{
        my $e = 1;
        sub { \$e };
    };
    my $cv  = clone $sub;

    is $cv->(), $sub->(), 'lexical from eval is copied';
}

{
    BEGIN { $tests += 1 }

    sub bc {
        {
            my $x;
            return sub { \$x };
        }
    }
    my $sub = bc;
    my $cv  = clone $sub;

    isnt $cv->(), $sub->(), 'lexical from block-in-sub is cloned';
}

{
    BEGIN { $tests += 1 }

    sub lpc {
        my @lc;
        for my $lc (1..2) {
            push @lc, sub { \$lc };
        }
        return $lc[0];
    }
    my $sub = lpc;
    my $cv  = clone $sub;

    isnt $cv->(), $sub->(), 'lexical from for-in-sub is cloned';
}

TODO: {
    $] >= 5.008 or local $TODO = q/lexicals in evals don't work under 5.6/;

    BEGIN { $tests += 1 }

    sub ec {
        my $x = 1;
        return eval q{ sub { \$x } };
    }
    my $sub = ec;
    my $cv  = clone $sub;

    isnt $cv->(), $sub->(), 'lexical from sub in eval-string is cloned';
}

{
    BEGIN { $tests += 1 }

    sub eec {
        return eval q{ my $x; sub { \$x } };
    }
    my $sub = eec;
    my $cv  = clone $sub;

    isnt $cv->(), $sub->(), 'lexical from eval-in-sub is cloned';
}

{
    BEGIN { $tests += 3 }

    sub ac {
        my $x;
        my $y = \$x;
        return sub { \$x }, sub { $y };
    }

    my $subs = [ ac ];
    my $cvs  = clone $subs;

    is   $subs->[0](), $subs->[1](), 'sanity check';
    isnt $subs->[0](), $cvs->[0](),  'lexical in closure in array is cloned';
    is   $cvs->[0](),  $cvs->[1](),  'co-cloned subs share lexicals';
}

my $gone;

BEGIN {
    package t::Gone;

    sub new { return bless [], $_[0]; }

    sub DESTROY { $gone++; }
}

{
    BEGIN { $tests += 2 }

    $gone = 0;

    {
        my $x = t::Gone->new;
        my $sub = sub { $x };
        my $cv  = clone $sub;

        ok !$gone, 'sanity check';
    }

    ok $gone == 1, 'copied lexical is destroyed';
}

{
    BEGIN { $tests += 3 }

    $gone = 0;

    sub leak_lex {
        my $x = t::Gone->new;
        return sub { $x };
    }

    {
        my $sub = leak_lex;
        my $cv  = clone $sub;

        ok !$gone, 'sanity check';
    }

    ok $gone,       'cloned lexical is destroyed';
    ok $gone == 2,  'both copies are destroyed';
}

BEGIN { plan tests => $tests }
