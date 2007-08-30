#!/usr/bin/perl

use warnings;
use strict;

use Test::More;
use Clone::Closure qw/clone/;
use Data::Dumper;

my $tests;

package Test::Array;

our @ISA = qw(Clone::Closure);

sub new {
    my $class = shift;
    my @self = @_;
    bless \@self, $class;
}

package main;
                                                
my $x = Test::Array->new(
    1, 
    [ 'two', 
      [ 3,
        ['four']
      ],
    ],
  );
my $y = $x->clone;

BEGIN { $tests += 2 }
is $y->[1][0],  'two',      'deep structure is copied';
isnt $y->[1],   $x->[1],    'refs are cloned, not copied';

my @circ;
$circ[0] = \@circ;
my $aref = clone \@circ;

BEGIN { $tests += 1 }
is Dumper(\@circ), Dumper($aref), 'circular refs are cloned';

# test for unicode support
{
    my $a = [ chr(256) => 1 ];
    my $b = clone( $a );
    BEGIN { $tests += 1 }
    is ord( $a->[0] ), ord( $b->[0] ), 'unicode is cloned';
}

BEGIN { plan tests => $tests }
