use 5.005;
use inc::Module::Install;
author          'David A. Golden <dagolden@cpan.org>';
all_from        'lib/Test/Reporter.pm';
requires        'Carp' => 0;
requires        'Cwd' => 0;
requires        'File::Temp' => 0;
requires        'FileHandle' => 0;
requires        'Net::SMTP' => 0;
requires        'Sys::Hostname' => 0;
requires        'Time::Local' => 0;
requires        'base' => 0;
requires        'constant' => 0;
build_requires  'Data::Dumper' => 0;
build_requires  'File::Find' => 0;
build_requires  'Test::More' => 0.47;
no_index        directory => 'xt';
bugtracker      'http://code.google.com/p/test-reporter/issues/list';
homepage        'http://code.google.com/p/test-reporter/';
license         'http://dev.perl.org/licenses/';
repository      'git://github.com/dagolden/test-reporter.git';
extra_tests;

WriteAll;

