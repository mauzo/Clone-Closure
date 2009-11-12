use inc::Module::Install;

name            'Clone-Closure';
license         'perl';
all_from        'lib/Clone/Closure.pm';

requires        'XSLoader'              => 0;
build_requires  'Test::More'            => '0.88';
build_requires  'Data::Dumper'          => 0;
build_requires  'Scalar::Util'          => '1.14';
build_requires  'Task::Weaken'          => 0
    if $ENV{AUTOMATED_TESTING};
build_requires  'Taint::Runtime'        => 0;
build_requires  'File::Temp'            => '0.16';

ppport;

makemaker_args INC => "-I.";

WriteAll;
