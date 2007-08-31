#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Clone::Closure  qw/clone/;
use Scalar::Util    qw/blessed refaddr/;
use B               qw/SVf_ROK/;

BEGIN { *b = \&B::svref_2object }

my $tests;

BEGIN { $tests += 3 }

my $scalar = 5;
my $rv = clone \$scalar;

isa_ok  b(\$rv),        'B::RV',        'RV cloned';
isnt    $rv,            \$scalar,       '...not copied';
is      $$rv,           5,              '...correctly';

BEGIN { $tests += 3 }

my $undef = clone \undef;

isa_ok  b(\$undef),     'B::RV',        'ref to undef cloned';
isnt    $undef,         \undef,         '...not copied';
ok      !defined($$undef),              '...correctly';

BEGIN { $tests += 3 }

my $circ;
$circ = \$circ;
my $crv = clone $circ;

isa_ok  b(\$crv),       'B::RV',        'circular ref cloned';
isnt    $crv,           \$circ,         '...not copied';
is      $$crv,          $crv,           '...correctly';

BEGIN { $tests += 4 }

my $obj     = 6;
my $blessed = bless \$obj, 'Foo';
my $brv     = clone $blessed;

isa_ok  b(\$brv),       'B::RV',        'blessed ref cloned';
is      blessed($brv),  'Foo',          '...preserving class';
isnt    refaddr($brv),  refaddr($blessed),
                                        '...not copied';
is      $$brv,          6,              '...correctly';

SKIP: {
    my $skip;
    eval 'use Scalar::Util qw/weaken isweak/; 1'
        or skip 'no weakrefs', $skip;

    BEGIN { $skip += 5 }
    
    # we need to have a real ref to the referent in the cloned
    # structure, otherwise it destructs.

    my $sv    = 5;
    my $weak  = [\$sv, \$sv];
    weaken($weak->[0]);
    my $wrv_c = blessed b \$weak->[0];
    my $wrv   = clone $weak;

    isa_ok  b(\$wrv->[0]),  $wrv_c,    'weakref cloned';
    ok      b(\$wrv->[0])->FLAGS & SVf_ROK,
                                        '...and a reference';
    ok      isweak($wrv->[0]),          '...preserving isweak';
    isnt    $wrv->[0],      \$sv,       '...not copied';
    is      ${$wrv->[0]},   5,          '...correctly';

    BEGIN { $skip += 5 }

    my $wcir;
    $wcir      = \$wcir;
    weaken($wcir);
    my $wcrv_c = blessed b \$wcir;
    my $wcrv   = clone \$wcir;

    isa_ok  b($wcrv),       $wcrv_c,    'weak circular ref cloned';
    ok      b($wcrv)->FLAGS & SVf_ROK,  '...and a reference';
    ok      isweak($$wcrv),             '...preserving isweak';
    isnt    $$wcrv,         \$wcir,     '...not copied';
    is      $$$wcrv,        $$wcrv,     '...correctly';

    BEGIN { $tests += $skip }
}

BEGIN { plan tests => $tests }
