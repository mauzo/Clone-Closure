#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Builder;
use Clone::Closure  qw/clone/;
use Scalar::Util    qw/blessed refaddr/;
use B               qw/SVf_ROK/;

BEGIN { *b = \&B::svref_2object }

my $tests;

{
    BEGIN { $tests += 3 }

    my $scalar = 5;
    my $rv = clone \$scalar;

    isa_ok  b(\$rv),        'B::RV',        'RV cloned';
    isnt    $rv,            \$scalar,       '...not copied';
    is      $$rv,           5,              '...correctly';
}

{
    BEGIN { $tests += 3 }

    my $rv = clone \undef;

    isa_ok  b(\$rv),     'B::RV',        'ref to undef cloned';
    is      $rv,         \undef,         '...as a copy';
    ok      !defined($$rv),              '...correctly';
}

{
    BEGIN { $tests += 3 }

    my $circ;
    $circ = \$circ;
    my $rv = clone $circ;

    isa_ok  b(\$rv),       'B::RV',        'circular ref cloned';
    isnt    $rv,           \$circ,         '...not copied';
    is      $$rv,          $rv,            '...correctly';
}

{
    BEGIN { $tests += 4 }

    my $obj     = 6;
    my $blessed = bless \$obj, 'Foo';
    my $rv     = clone $blessed;

    isa_ok  b(\$rv),       'B::RV',        'blessed ref cloned';
    is      blessed($rv),  'Foo',          '...preserving class';
    isnt    refaddr($rv),  refaddr($blessed),
                                            '...not copied';
    is      $$rv,          6,               '...correctly';
}

BAIL_OUT 'refs won\'t clone correctly'
    if grep !$_, Test::Builder->new->summary;

{
    BEGIN { $tests += 2 }

    my $rv = clone *STDOUT{IO};

    isa_ok  b($rv),         'B::IO',        'PVIO cloned';
    is      $rv,            *STDOUT{IO},    '...and is a copy';
}

{
    BEGIN { $tests += 2 }

format PVFM =
foo
.
    my $rv = clone *PVFM{FORMAT};

    isa_ok  b($rv),         'B::FM',        'PVFM cloned';
    is      $rv,            *PVFM{FORMAT},  '...and is a copy';
}

{
    BEGIN { $tests += 6 }

    my $glob = *bar;
    my $gv   = clone *bar;

    isa_ok  b(\$gv),        'B::GV',        'GV cloned';
    is      b(\$glob)->GP,  b(\*bar)->GP,   'sanity check';
    is      b(\$gv)->GP,    b(\*bar)->GP,   '...and is the same glob';

    my $rv = clone \*foo;

    isa_ok  b(\$rv),        'B::RV',        'ref to GV cloned';
    isa_ok  b($rv),         'B::GV',        'GV cloned';
    is      $rv,            \*foo,          '...and is copied';
}

SKIP: {
    my $skip;
    eval 'use Scalar::Util qw/weaken isweak/; 1'
        or skip 'no weakrefs', $skip;

    {
        BEGIN { $skip += 5 }
        
        # we need to have a real ref to the referent in the cloned
        # structure, otherwise it destructs.

        my $sv    = 5;
        my $weak  = [\$sv, \$sv];
        weaken($weak->[0]);
        my $type  = blessed b \$weak->[0];
        my $rv   = clone $weak;

        isa_ok  b(\$rv->[0]),  $type,      'weakref cloned';
        ok      b(\$rv->[0])->FLAGS & SVf_ROK,
                                           '...and a reference';
        ok      isweak($rv->[0]),          '...preserving isweak';
        isnt    $rv->[0],      \$sv,       '...not copied';
        is      ${$rv->[0]},   5,          '...correctly';
    }

    {
        BEGIN { $skip += 5 }

        my $circ;
        $circ    = \$circ;
        weaken($circ);
        my $type = blessed b \$circ;
        my $rv   = clone \$circ;

        isa_ok  b($rv),       $type,      'weak circular ref cloned';
        ok      b($rv)->FLAGS & SVf_ROK,  '...and a reference';
        ok      isweak($$rv),             '...preserving isweak';
        isnt    $$rv,         \$circ,     '...not copied';
        is      $$$rv,        $$rv,       '...correctly';
    }

    BEGIN { $tests += $skip }
}

BEGIN { plan tests => $tests }
