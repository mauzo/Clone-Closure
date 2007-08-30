#!/usr/bin/perl

use warnings;
use strict;

use Test::More;
use Data::Dumper;
use Clone::Closure qw/clone/;

my $tests;

package Test::Hash;

our @ISA = qw(Clone::Closure);

sub new {
    my $class = shift;
    my %self = @_;
    bless \%self, $class;
}

package main;
                                                
my $x = Test::Hash->new(
    level => 1,
    href  => {
      level => 2,
      href  => {
        level => 3,
        href  => {
          level => 4,
        },
      },
    },
  );

$x->{a} = $x;
my $y = $x->clone;

BEGIN { $tests += 5 }
is   $x->{level},   $y->{level},    'blessed hashes are cloned';
isnt $y->{href},    $x->{href},     'hashrefs are cloned, not copied';
isnt $y->{href}{href},
     $x->{href}{href},              '...at every level';
is   $y->{href}{href}{level}, 3,    'recursive hrefs are cloned';
isnt $y->{href}{href}{href},
     $x->{href}{href}{href},        '...not copied';

my %circ = ();
$circ{c} = \%circ;
my $cref = clone(\%circ);

BEGIN { $tests += 1 }
is Dumper(\%circ), Dumper($cref),   'circular hrefs are cloned';

# test for unicode support
{
    my $x = { chr(256) => 1 };
    my $y = clone( $x );

    BEGIN { $tests += 1 }
    is ord( (keys(%$x))[0] ), ord( (keys(%$y))[0] ), 'unicode hash keys';
}

BEGIN { plan tests => $tests }
