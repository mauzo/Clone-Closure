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

SKIP: {
    my $skip;
    skip '*FOO{FORMAT} does not work under 5.6', $skip
        if $] < 5.008;

    BEGIN { $skip += 2 }

format PVFM =
foo
.
    my $rv = clone *PVFM{FORMAT};

    isa_ok  b($rv),         'B::FM',        'PVFM cloned';
    is      $rv,            *PVFM{FORMAT},  '...and is a copy';

    BEGIN { $tests += $skip }
}

BEGIN { plan tests => $tests }
