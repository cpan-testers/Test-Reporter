use ExtUtils::MakeMaker;

my $extra_meta = <<EOF;
resources:
    license: http://dev.perl.org/licenses/
    homepage: http://code.google.com/p/test-reporter/
    bugtracker: http://code.google.com/p/test-reporter/issues/list
    Repository: http://echo.dagolden.com/git/?p=Test-Reporter
    MailingList: http://groups.google.com/group/test-reporter
EOF

WriteMakefile(
#    (MM->can('signature_target') ? (SIGN => 1) : ()),
    'NAME' => 'Test::Reporter',
    'PREREQ_PM' => {
        'Test::More' => 0.47,
        'Test'      => 0,
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
            AUTHOR => 'David Golden <dagolden@cpan.org>',
        ) : ()
    ),
    'clean' => {
        'FILES' => '*.rpt',
    },
    ($ExtUtils::MakeMaker::VERSION >= 6.31 ? (LICENSE => 'perl') : ()),
    ($ExtUtils::MakeMaker::VERSION >= 6.36 ? (EXTRA_META => $extra_meta) : ()),
);
