#!/usr/bin/perl

use strict;
use warnings;

BEGIN { eval "use threads" }

use Scalar::Util    qw/blessed tainted reftype/;
use Test::More;
use B               qw/SVf_ROK/;
use ExtUtils::MM;
use Clone::Closure  qw/clone/;

BEGIN { *b = \&B::svref_2object }

use constant        SVp_SCREAM => 0x08000000;

sub mg {
    my %mg;
    my $mg = eval { b($_[0])->MAGIC };

    while ($mg) {
        $mg{ $mg->TYPE } = $mg;
        $mg = $mg->MOREMAGIC;
    }

    return \%mg;
}

sub _test_mg {
    my ($invert, $ref, $how, $name) = ($_[0], \$_[1], @_[2,3]);

    my $mg  = mg $ref;
    my $got = join '', keys %$mg;

    my $ok  = $mg->{$how};
    my $diag;

    if ($invert) {
        $ok   = !$ok;
        $diag = <<DIAG;
Expected no magic of type
    '$how',
got magic of types
    '$got'.
DIAG
    }
    else {
        $diag = <<DIAG;
Expected magic of type
    '$how',
got magic of types
    '$got'.
DIAG
    }

    local $Test::Builder::Level = $Test::Builder::Level + 2;
    return ok($ok, $name) || diag($diag);
}

sub has_mg   { _test_mg 0, @_; }
sub hasnt_mg { _test_mg 1, @_; }

sub oneliner {
    my ($perl) = @_;
    my $cmd = "$^X -e " . MM->quote_literal($perl);
    my $val = qx/$cmd/;
    $? and $val = "qx/$cmd/ failed with \$? = $?";
    return $val;
}

my $tests;

# Types of magic (from perl.h)

#define PERL_MAGIC_sv		  '\0' /* Special scalar variable */
{
    BEGIN { $tests += 2 }

    my $mg = clone $0;

    hasnt_mg    $mg,        "\0",           '$0 loses magic';
    is          $mg,        $0,             '...but keeps value';
}

#define PERL_MAGIC_overload	  'A' /* %OVERLOAD hash */
#define PERL_MAGIC_overload_elem  'a' /* %OVERLOAD hash element */
#define PERL_MAGIC_overload_table 'c' /* Holds overload table (AMT) on stash */

#define PERL_MAGIC_bm		  'B' /* Boyer-Moore (fast string search) */
{
    BEGIN { $tests += 6 }

    use constant PVBM => 'foo';

    my $dummy  = index 'foo', PVBM;
    # blead (5.9) doesn't have PVBM, and uses PVGV instead
    my $type   = blessed b(\PVBM);
    my $pvbm   = clone PVBM;

    isa_ok  b(\$pvbm),      $type,      'PVBM cloned';
    has_mg  $pvbm,          'B',        '...with magic';
    is      $pvbm,          'foo',      '...and value';
    is      eval { b(\$pvbm)->RARE },
            b(\PVBM)->RARE,             '...and RARE';
    is      eval { b(\$pvbm)->TABLE },
            b(\PVBM)->TABLE,            '...and TABLE';
    is      index('foo', $pvbm),    0,  '...and still works';
}

#define PERL_MAGIC_regdata	  'D' /* Regex match position data
#					(@+ and @- vars) */
#define PERL_MAGIC_regdatum	  'd' /* Regex match position data element */
{
    BEGIN { $tests += 4 }

    use Data::Dump qw/dump/;

    "foo" =~ /foo/;
    my $Dmg = clone \@+;
    my $dmg = clone $+[0];

    diag '\@+  = ' . dump \@+;
    diag '$Dmg = ' . dump $Dmg;

    hasnt_mg    $Dmg,       'D',        '@+ loses magic';
    is_deeply   $Dmg,       \@+,        '...but keeps value';
    hasnt_mg    $dmg,       'd',        '$+[0] loses magic';
    is          $dmg,       $+[0],      '...but keeps value';
}

#define PERL_MAGIC_env		  'E' /* %ENV hash */
#define PERL_MAGIC_envelem	  'e' /* %ENV hash element */
{
    BEGIN { $tests += 6 }

    $ENV{FOO} = 'BAR';
    $ENV{BAR} = 'BAZ';
    my $Emg   = clone \%ENV;
    my $emg   = clone $ENV{FOO};

    sub real_getenv { oneliner "print \$ENV{'$_[0]'}" }

    hasnt_mg    $Emg,       'E',        '%ENV loses magic';
    is_deeply   $Emg,       \%ENV,      '...but keeps value';
    hasnt_mg    $emg,       'e',        '$ENV{FOO} loses magic';
    is          $emg,       'BAR',      '...but keeps value';

    $Emg->{BAR} = 'QUUX';
    $emg        = 'ZPORK';

    is      real_getenv('BAR'), 'BAZ',  '%ENV preserved';
    is      real_getenv('FOO'), 'BAR',  '$ENV{FOO} preserved';
}

#define PERL_MAGIC_fm		  'f' /* Formline ('compiled' format) */

#define PERL_MAGIC_regex_global	  'g' /* m//g target / study()ed string */
{
    BEGIN { $tests += 3 }

    my $str = 'foo';
    study $str;
    my $mg  = clone $str;

    hasnt_mg  $mg,        'g',          'studied string loses magic';
    ok  !(b(\$mg)->FLAGS & SVp_SCREAM), '...and SCREAM';    
    is        $mg,        $str,         '...but keeps value';
}

#define PERL_MAGIC_isa		  'I' /* @ISA array */
#define PERL_MAGIC_isaelem	  'i' /* @ISA array element */
{
    BEGIN { $tests += 4 }

    use vars qw/@ISA/;

    local @ISA;
    push @ISA, 't';

    my $Img = clone \@ISA;
    my $img = clone $ISA[0];

    hasnt_mg    $Img,       'I',        '@ISA loses magic';
    is_deeply   $Img,       \@ISA,      '...but keeps value';
    hasnt_mg    $img,       'i',        '$ISA[0] loses magic';
    is          $img,       $ISA[0],    '...but keeps value';
}

#define PERL_MAGIC_nkeys	  'k' /* scalar(keys()) lvalue */
{
    BEGIN { $tests += 3 }

    my %h = qw/a b c d/;
    my $mg = clone \scalar keys %h;

    hasnt_mg    $$mg,       'k',        'keys() loses magic';
    is          $$mg,       keys(%h),   '...but keeps value';

    $$mg = 10;

    is          keys(%h),   2,          'keys() preserved';
}

#define PERL_MAGIC_dbfile	  'L' /* Debugger %_<filename */
#define PERL_MAGIC_dbline	  'l' /* Debugger %_<filename element */
#define PERL_MAGIC_mutex	  'm' /* for lock op */
#define PERL_MAGIC_shared	  'N' /* Shared between threads */
#define PERL_MAGIC_shared_scalar  'n' /* Shared between threads */
#define PERL_MAGIC_collxfrm	  'o' /* Locale transformation */
#define PERL_MAGIC_tied		  'P' /* Tied array or hash */
#define PERL_MAGIC_tiedelem	  'p' /* Tied array or hash element */
#define PERL_MAGIC_tiedscalar	  'q' /* Tied scalar or handle */
#define PERL_MAGIC_qr		  'r' /* precompiled qr// regex */

#define PERL_MAGIC_sig		  'S' /* %SIG hash */
#define PERL_MAGIC_sigelem	  's' /* %SIG hash element */
{
    no warnings 'signal';
    my $HAS_USR1 = exists $SIG{USR1};

    my $count;
    $SIG{USR1} = sub { $count++ };
    my $Smg    = clone \%SIG;
    my $smg    = \clone $SIG{USR1};

    BEGIN { $tests += 4 }

    my $usr1 = $Smg->{USR1};
    $count = 0;

    hasnt_mg    $Smg,       'S',        '%SIG loses magic';
    is      reftype($usr1), 'CODE',     '...but value is cloned'
        and $usr1->();
    isnt    $Smg->{USR1},   $SIG{USR1}, '...not copied';
    is          $count,     1,          '...correctly';

    BEGIN { $tests += 4 }

    $count = 0;

    hasnt_mg    $$smg,      's',        '$SIG{USR1} loses magic';
    is      reftype($$smg), 'CODE',     '...but value is cloned'
        and ($$smg)->();
    isnt        $$smg,      $SIG{USR1}, '...not copied';
    is          $count,     1,          '...but value is cloned';

    BEGIN { $tests += 2 }

    SKIP: {
        my $skip;
        skip 'no SIGUSR1', 2 unless $HAS_USR1;

        $Smg->{USR1} = sub { 1; };
        $count = 0;
        kill USR1 => $$;

        is      $count,     1,          '%SIG preserved';

        $$smg = sub { 1; };
        $count = 0;
        kill USR1 => $$;

        is      $count,     1,          '$SIG{USR1} preserved';
    }
}

#define PERL_MAGIC_taint	  't' /* Taintedness */
#define PERL_MAGIC_uvar		  'U' /* Available for use by extensions */
#define PERL_MAGIC_uvar_elem	  'u' /* Reserved for use by extensions */

#define PERL_MAGIC_vstring	  'V' /* SV was vstring literal */
{
    BEGIN { $tests += 3 }

    my $vs = v1.2.3;
    my $mg = clone $vs;

    has_mg  $mg,            'V',        'vstring keeps magic';
    is      $mg,            $vs,        '...and value';
    is      eval { mg(\$mg)->{V}->PTR },   
            mg(\$vs)->{V}->PTR,         '...correctly';
}

#define PERL_MAGIC_vec		  'v' /* vec() lvalue */
{
    BEGIN { $tests += 3 }

    my $str = 'aaa';
    my $mg  = clone \vec $str, 1, 8;

    hasnt_mg    $$mg,       'v',        'vec() loses magic';
    is          $$mg,       ord('a'),   '...but keeps value';

    $$mg = ord('b');

    is          $str,       'aaa',      'vec() preserved';
}

#define PERL_MAGIC_utf8		  'w' /* Cached UTF-8 information */
SKIP: {
    my $skip;

    my $str = "\x{fff}a";
    my $dummy = index $str, 'a';
    
    mg(\$str)->{w} or skip 'no utf8 cache', $skip;
    skip 'utf8 segfaults', $skip;

    BEGIN { $skip += 3 }

    my $mg = clone $str;

    has_mg  $mg,            'w',        'utf8 cache is cloned';
    is      $mg,            $str,       '...with value';
    is      eval { mg(\$mg)->{w}->PTR },
            mg(\$str)->{w}->PTR,        '...correctly';
    
    BEGIN { $tests += $skip }
}

#define PERL_MAGIC_substr	  'x' /* substr() lvalue */
{
    BEGIN { $tests += 3 }

    my $str = 'aabbc';
    my $mg  = clone \substr $str, 3, 2;

    hasnt_mg    $$mg,       'x',        'substr() loses magic';
    is          $$mg,       'bb',       '...but keeps value';

    $$mg = 'dd';

    is          $str,       'aabbc',    'substr() preserved';
}

#define PERL_MAGIC_defelem	  'y' /* Shadow "foreach" iterator variable /
#					smart parameter vivification */
{
    BEGIN { $tests += 3 }

    sub defelem { return \$_[0] }

    my %hash;
    my $mg = clone defelem $hash{a};

    hasnt_mg    $$mg,       'y',        'autoviv loses magic';
    ok          !defined($$mg),         '...is still undef';

    $$mg = 'a';

    ok          !exists($hash{a}),      'autoviv preserved';
}

#define PERL_MAGIC_glob		  '*' /* GV (typeglob) */
{
    BEGIN { $tests += 4 }

    my $glob = *bar;
    my $gv   = clone *bar;

    isa_ok  b(\$gv),        'B::GV',        'GV cloned';
    has_mg  $gv,            '*',            '...with magic';
    SKIP: {
        skip 'can\'t test globs', 2
            unless eval { b(\*STDOUT)->GP; 1 };

        is      b(\$glob)->GP,  b(\*bar)->GP,   '(sanity check)';
        is      b(\$gv)->GP,    b(\*bar)->GP,   '...and is the same glob';
    }

    BEGIN { $tests += 4 }

    my $rv = clone \*foo;

    isa_ok  b(\$rv),        'B::RV',        'ref to GV cloned';
    isa_ok  b($rv),         'B::GV',        'GV cloned';
    has_mg  *$rv,           '*',            '...with magic';
    is      $rv,            \*foo,          '...and is copied';
}

#define PERL_MAGIC_arylen	  '#' /* Array length ($#ary) */
{
    BEGIN { $tests += 3 }

    my @ary = qw/a b c/;
    my $mg  = clone \$#ary;

    hasnt_mg    $$mg,       '#',            '$#ary loses magic';
    is          $$mg,       $#ary,          '...but keeps value';

    $$mg = 5;

    is          $#ary,      2,              '$#ary preserved';
}

#define PERL_MAGIC_pos		  '.' /* pos() lvalue */
{
    BEGIN { $tests += 3 }

    my $str = 'fffgh';
    $str =~ /f*/g;
    my $mg  = \clone pos($str);

    hasnt_mg    $$mg,       '.',            'pos() loses magic';
    is          $$mg,       pos($str),      '...but keeps value';

    $$mg = 0;

    is          pos($str),  3,              'pos() preserved';
}

#define PERL_MAGIC_backref	  '<' /* for weak ref data */
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

        my $weak = [5, undef];
        $weak->[1] = \$weak->[0];
        weaken($weak->[1]);

        my $type = blessed b \$weak->[0];
        my $rv   = clone $weak;

        isa_ok  b(\$rv->[0]),   $type,      'weak referent cloned';
        isnt    \$rv->[0],      \$weak->[0],    '...not copied';
        ok      isweak($rv->[1]),           '...preserving isweak';
        has_mg  $rv->[0],       '<',        '...with magic';
        is      $rv->[0],       5,          '...correctly';
    }

    {
        BEGIN { $skip += 6 }

        my $circ;
        $circ    = \$circ;
        weaken($circ);
        my $type = blessed b \$circ;
        my $rv   = clone \$circ;

        isa_ok  b($rv),         $type,      'weak circular ref cloned';
        ok      b($rv)->FLAGS & SVf_ROK,    '...and a reference';
        has_mg  $rv,            '<',        '...with magic';
        ok      isweak($$rv),               '...preserving isweak';
        isnt    $$rv,           \$circ,     '...not copied';
        is      $$$rv,          $$rv,       '...correctly';
    }

    BEGIN { $tests += $skip }
}

#define PERL_MAGIC_ext		  '~' /* Available for use by extensions */

BEGIN { plan tests => $tests }
