use inc::Module::Install;

name            'Clone-Closure';
license         'perl';
all_from        'lib/Clone/Closure.pm';

requires        XSLoader => 0;

ppport;

auto_install;
WriteAll;
