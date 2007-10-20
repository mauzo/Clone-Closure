use inc::Module::Install;

name            'Clone-Closure';
license         'perl';
all_from        'lib/Clone/Closure.pm';

if ($] > 5.009) {
    require Config;
    if ($Config::Config{perl_patchlevel} < 32121) {
        warn "This perl has a bug in PVBM handling\n";
        exit 0;
    }
}

requires        'XSLoader'              => 0;
build_requires  'Test::More'            => '0.68';
build_requires  'Data::Dumper'          => 0;
build_requires  'Scalar::Util'          => '1.14';
build_requires  'Task::Weaken'          => 0
    if $ENV{AUTOMATED_TESTING};
build_requires  'Taint::Runtime'        => 0;
build_requires  'File::Temp'            => '0.16';

ppport;

auto_install;
WriteAll;
