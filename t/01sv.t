#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Clone::Closure qw/clone/;
use Scalar::Util   qw/blessed/;
use B qw{
    svref_2object
    SVf_IVisUV
};

sub b {
    return svref_2object $_[0];
}

my $tests;

BEGIN { $tests += 1 }
my $undef = clone undef;
ok      !defined $undef,            'undef clones';

BEGIN { $tests += 2 }
my $iv = clone 2;
isa_ok  b(\$iv),    'B::IV',        'IV clones';
is      $iv,        2,              '...correctly';

BEGIN { $tests += 3 }
my $uv = clone 1<<63;
isa_ok  b(\$uv),    'B::IV',        'IVisUV clones';
is      $uv,        1<<63,          '...correctly';
is      b(\$uv)->FLAGS       & SVf_IVisUV,
        b( \(1<<63) )->FLAGS & SVf_IVisUV,
                                    '...preserving IVisUV';
BEGIN { $tests += 2 }
my $nv = clone 2.2;
isa_ok  b(\$nv),    'B::NV',        'NV clones';
is      $nv,        2.2,            '...correctly';

BEGIN { $tests += 2 }
my $pv = clone 'hello world';
isa_ok  b(\$pv),    'B::PV',        'PV clones';
is      $pv,        'hello world',  '...correctly';

BEGIN { $tests += 6 }
SKIP: {
    eval 'require utf8';
    defined &utf8::is_utf8 or skip 'no utf8 support', 6;

    my $utf8 = clone "\x{fff}";
    isa_ok  b(\$utf8),  'B::PV',    'utf8 clones';
    ok      utf8::is_utf8($utf8),   '...preserving utf8';
    is      $utf8,      "\x{fff}",  '...correctly';

    my $ascii = 'foo';
    utf8::upgrade($ascii);
    my $upg   = clone $ascii;

    isa_ok  b(\$upg),   'B::PV',    'upgraded utf8 clones';
    ok      utf8::is_utf8($upg),    '...preserving utf8';
    is      $upg,       'foo',      '...correctly';
}

SKIP: {
    eval 'use Scalar::Util qw/dualvar/; 1'
        or skip 'no dualvar support', 6;

    BEGIN { $tests += 3 }

    my $dualvar = dualvar(5, 'bar');
    # dualvar sometimes seems to make a PVNV when it doesn't need to
    my $pviv_c  = blessed b(\$dualvar);
    my $pviv = clone $dualvar;

    isa_ok  b(\$pviv),  $pviv_c,    'PVIV clones';
    cmp_ok  $pviv, '==', 5,         '...correctly';
    is      $pviv,      'bar',      '...correctly';

    BEGIN { $tests += 3 }
    my $pvnv = clone dualvar(3.1, 'baz');
    isa_ok  b(\$pvnv),  'B::PVNV',  'PVNV clones';
    cmp_ok  $pvnv, '==', 3.1,       '...correctly';
    is      $pvnv,      'baz',      '...correctly';
}

BEGIN { $tests += 2 }

use constant PVBM => 'foo';

my $dummy  = index 'foo', PVBM;
# blead (5.9) doesn't have PVBM
my $pvbm_c = blessed b(\PVBM);
my $pvbm   = clone PVBM;

isa_ok  b(\$pvbm),      $pvbm_c,    'PVBM clones';
is      $pvbm,          'foo',      '...correctly';

# PVLV is surprisingly hard to test... it tends to vanish :(
BEGIN { $tests += 4 }

my $foo  = 'foo';
isa_ok  b(\( substr $foo, 0, 2 )),
                        'B::PVLV',  'sanity check';
isa_ok  b(\( clone substr $foo, 0, 2 )),
                        'B::PVLV',  'PVLV clones';
is      clone(substr $foo, 0, 2),
                        'fo',       '...correctly';

sub set_lvalue { $_[0] = 'got' }
set_lvalue clone substr $foo, 0, 2;
is      $foo,           'goto',     '...preserving lvalue';

BEGIN { plan tests => $tests }
