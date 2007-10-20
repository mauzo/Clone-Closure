package Clone::Closure;

use 5.006001;

use strict;
use Carp;

use base 'Exporter';
our @EXPORT_OK = qw( clone );

our $VERSION = '0.01_01';

use XSLoader;
XSLoader::load __PACKAGE__, $VERSION;

$VERSION = eval $VERSION;

1;
__END__

=head1 NAME

Clone::Closure - A clone that knows how to clone closures

=head1 SYNOPSIS

    use Clone::Closure qw/clone/;

    my $total;

    sub count {
        my $count;
        return sub { $count++, $total++ };
    }

    my $foo = count;
    my $bar = clone $foo;

    # $bar has its own copy of $count, but shares $total 
    # with $foo.

=head1 DESCRIPTION

This module provides a C<clone> method which makes recursive
copies of nested hash, array, scalar and reference types, 
including tied variables, objects, and closures.

C<clone> takes a scalar argument and an optional parameter that 
can be used to limit the depth of the copy. To duplicate lists,
arrays or hashes, pass them in by reference. e.g.
    
    my $copy = clone \@array;

    # or

    my %copy = %{ clone \%hash };

Closures are cloned, unlike with L<Clone|Clone>. Closed-over lexicals
will be cloned if they were originally declared in a scope that could be
run more than once, and shared otherwise. 

That is, in the example in the
L</SYNOPSIS>, $count is cloned as it is scoped to &count, which can run
many times with different $count variables; but $total is shared as it
is file-scoped, so there will only ever be one copy. 

Generally speaking, C<clone> will produce what might have been another
copy of the closure, generated by the same means. However, see L</BUGS>
below.

=head1 BUGS

=head2 Loops

Loops are currently not correctly recognized as 'scopes that may run
more than once'. That is, given

    my @subs;

    for my $i (1..10) {
        push @subs, sub { $i };
    }

a clone of $subs[0] will B<share> $i, which is probably not what you
wanted. One possible workaround is to generate the closure in a sub,
with its own lexical; for example

    my @subs;

    sub make_closure {
        # this is important, so we get a new lexical
        my $i = shift;
        
        return sub { $i };
    }

    for my $i (1..10) {
        push @subs, make_closure $i;
    }

A clone of $subs[0] will now have its own copy of $i.

=head2 5.6 and C<eval I<STRING>>

Under 5.6, lexicals which are closed over by C<eval I<STRING>> will
always be cloned, never shared. That is, given

    my $x;
    my $sub = eval 'sub { $x }';

a clone of $sub will have its own copy of $x, which is incorrect.

=head1 AUTHOR

This module is based on Clone v0.23 by Ray Finch, <rdf@cpan.org>.

Clone is copyright 2001 Ray Finch.

This module is copyright 2007 Ben Morrow, <ben@morrow.me.uk>.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Clone|Clone>, L<Storable|Storable>.

=cut
