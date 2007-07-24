use ExtUtils::MakeMaker;
# $Id: Makefile.PL,v 0.18 2006-10-08 03:37:20 ray Exp $
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	=> 'Clone::Closure',
    'VERSION_FROM' => 'lib/Clone/Closure.pm', # finds $VERSION
    'LIBS'	=> [''],   # e.g., '-lm' 
    'DEFINE'	=> '',     # e.g., '-DHAVE_SOMETHING' 
    'INC'	=> '',     # e.g., '-I/usr/include/other' 
#    'OPTIMIZE'	=> '-g',     # e.g., '-I/usr/include/other' 
    'OPTIMIZE'	=> '-O3',     # e.g., '-I/usr/include/other' 
);

