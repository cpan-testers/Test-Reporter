# $Id: Makefile.PL 63 2007-06-27 07:21:12Z afoxson $
# $HeadURL: https://test-reporter.googlecode.com/svn/branches/1.30/Makefile.PL $

use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'Test::Reporter',
    'PM' => {
        'lib/Test/Reporter.pm' => '$(INST_LIBDIR)/Reporter.pm',
    },
    'PREREQ_PM' => {
        'Net::SMTP' => 0,
        'File::Temp' => 0,
        'File::Spec' => 0,
    },
    'VERSION_FROM' => 'lib/Test/Reporter.pm',
    'dist' => {
        'COMPRESS' => 'gzip --best',
        'SUFFIX' => '.gz',
    },
    EXE_FILES => ['bin/cpantest'],
    (   
        $] >= 5.005 ?  (   
            ABSTRACT_FROM => 'lib/Test/Reporter.pm',
            AUTHOR => 'Adam J. Foxson <afoxson@pobox.com>',
        ) : ()
    ),
    'clean' => {
        'FILES' => '*.rpt',
    },
    LICENSE => 'perl',
);
