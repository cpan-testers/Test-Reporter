#!/usr/bin/perl -w

use strict;
use FileHandle;
use Test::More;
use Test::Reporter;

plan tests => 129;

my $distro = sprintf "Test-Reporter-%s", $Test::Reporter::VERSION;

my $reporter = Test::Reporter->new();
isa_ok($reporter, 'Test::Reporter');

$reporter->grade('pass');
$reporter->distribution('Mail-Freshmeat-1.20');

like($reporter->subject, '/^PASS Mail-Freshmeat-1.20\s/');
like($reporter->report, '/This distribution has been tested/');
like($reporter->report, '/Summary of my/');
is($reporter->grade, 'pass');
is($reporter->distribution, 'Mail-Freshmeat-1.20');
is($reporter->timeout, 120);

undef $reporter;

$reporter = Test::Reporter->new();
isa_ok($reporter, 'Test::Reporter');

$reporter->grade('fail');
$reporter->distribution('Foo-Bar-1.50');
$reporter->comments('blah');
$reporter->timeout(60);
$reporter->via('CPANPLUS');
$reporter->from('foo@bar.com');
$reporter->address('send@reports.here');
$reporter->mx([1, 2, 3, 4, 5, 6, 7, 8, 9]);

like($reporter->subject, '/^FAIL Foo-Bar-1.50\s/');
like($reporter->report, '/This distribution has been tested/');
like($reporter->report, '/Summary of my/');
like($reporter->report, '/blah/');
is($reporter->grade, 'fail');
is($reporter->distribution, 'Foo-Bar-1.50');
is($reporter->timeout, 60);
is($reporter->comments, 'blah');
is($reporter->via, 'CPANPLUS');
is($reporter->from, 'foo@bar.com');
is($reporter->address, 'send@reports.here');
is($reporter->debug, 0);
is(scalar @{$reporter->mx}, 9);

undef $reporter;

$reporter = Test::Reporter->new();
isa_ok($reporter, 'Test::Reporter');

$reporter->grade('na');
is($reporter->grade, 'na');
is($reporter->timeout, 120);

undef $reporter;

$reporter = Test::Reporter->new();
isa_ok($reporter, 'Test::Reporter');

$reporter->grade('unknown');
is($reporter->grade, 'unknown');

undef $reporter;

$reporter = Test::Reporter->new
(
    mx => [1, 2, 3, 4, 5],
    address => 'foo@bar',
    grade => 'pass',
    distribution => 'Bar-1.0',
    from => 'me@me.com',
    comments => 'woo',
    via => 'something',
    timeout => 500,
    debug => 0,
    dir => '/tmp',
);
isa_ok($reporter, 'Test::Reporter');
like($reporter->subject, '/^PASS Bar-1.0\s/');
like($reporter->report, '/This distribution has been tested/');
like($reporter->report, '/Summary of my/');
like($reporter->report, '/woo/');
is($reporter->grade, 'pass');
is($reporter->distribution, 'Bar-1.0');
is($reporter->timeout, 500);
is($reporter->comments, 'woo');
is($reporter->via, 'something');
is($reporter->from, 'me@me.com');
is($reporter->address, 'foo@bar');
is($reporter->debug, 0);
is(scalar @{$reporter->mx}, 5);
is($reporter->dir, '/tmp');

# ---

undef $reporter;

$reporter = Test::Reporter->new
(
    grade => 'pass',
    distribution => $distro,
    from => 'johndoe@example.net',
);
isa_ok($reporter, 'Test::Reporter');
my $file = $reporter->write();
like($file, '/Test-Reporter/');
ok(-e $file);

my $orig_subject = $reporter->subject;
my $orig_from = $reporter->from;
my $orig_report = $reporter->report;

undef $reporter;

$reporter = Test::Reporter->new
(
)->read($file);
isa_ok($reporter, 'Test::Reporter');
like($reporter->subject,"/^PASS $distro\\s/");
like($reporter->report, '/This distribution has been tested/');
like($reporter->report,'/Summary of my/');
is($reporter->grade, 'pass');
is($reporter->distribution, $distro);

# confirm roundtrip -- particularly newlines
is($reporter->subject, $orig_subject);
is($reporter->from, $orig_from);
is($reporter->report, $orig_report);

unlink $file;

# testing perl-version with the current perl
my $alt_perl = 'alt_perl.pl';
my $no_version = $reporter->perl_version;
my $same_version = $reporter->perl_version($^X);
for my $field ( qw( _archname _osvers _myconfig) )
  { is( $no_version->{$field}, $same_version->{$field}); }

# testing perl-version with a fake perl
# create fake perl
{
    my $fh = FileHandle->new();
    open( $fh, ">$alt_perl") or die "cannot create (fake) $alt_perl: $!";
    # fake perl, still needs to grab the magick number!
    print {$fh} qq{(\$m= join( '', \@ARGV))=~ s{\\D}{}g; print "\$m\nnew_archname\nnew_osvers\nnew_myconfig\n(several lines)"; };
    close $fh;

    my $alt_perl_version = $reporter->perl_version("$^X $alt_perl");
    is( $reporter->perl_version->{_archname}, 'new_archname');
    is( $reporter->perl_version->{_osvers}, 'new_osvers');
    like( $reporter->perl_version->{_myconfig}, '/^new_myconfig\n\(several lines\)/s'); # VMS has trailing CRLF

    1 while (unlink $alt_perl);
}

# testing error
{
    my $fh = FileHandle->new();
    open( $fh, ">$alt_perl") or die "cannot create (fake, not working) $alt_perl: $!";
    # fake perl, gives wrong output
    print {$fh} qq{print "booh"; };
    close $fh;

    eval { $reporter->perl_version( "$^X $alt_perl"); };
    like($@, q{/^Test::Reporter: cannot get perl version info from/});
    1 while (unlink $alt_perl);
}

ok($reporter->_is_a_perl_release('perl-5.9.3'));
ok($reporter->_is_a_perl_release('perl-5.9.2'));
ok($reporter->_is_a_perl_release('perl-5.9.1'));
ok($reporter->_is_a_perl_release('perl-5.9.0'));
ok($reporter->_is_a_perl_release('perl-5.8.7'));
ok($reporter->_is_a_perl_release('perl-5.8.6'));
ok($reporter->_is_a_perl_release('perl-5.8.5'));
ok($reporter->_is_a_perl_release('perl-5.8.4'));
ok($reporter->_is_a_perl_release('perl-5.8.3'));
ok($reporter->_is_a_perl_release('perl-5.8.2'));
ok($reporter->_is_a_perl_release('perl-5.8.1'));
ok($reporter->_is_a_perl_release('perl-5.8.0'));
ok($reporter->_is_a_perl_release('perl-5.7.3'));
ok($reporter->_is_a_perl_release('perl-5.7.2'));
ok($reporter->_is_a_perl_release('perl-5.7.1'));
ok($reporter->_is_a_perl_release('perl-5.7.0'));
ok($reporter->_is_a_perl_release('perl-5.6.2'));
ok($reporter->_is_a_perl_release('perl-5.6.1-TRIAL3'));
ok($reporter->_is_a_perl_release('perl-5.6.1-TRIAL2'));
ok($reporter->_is_a_perl_release('perl-5.6.1-TRIAL1'));
ok($reporter->_is_a_perl_release('perl-5.6.1'));
ok($reporter->_is_a_perl_release('perl-5.6.0'));
ok($reporter->_is_a_perl_release('perl-5.6-info'));
ok($reporter->_is_a_perl_release('perl5.005_04'));
ok($reporter->_is_a_perl_release('perl5.005_03'));
ok($reporter->_is_a_perl_release('perl5.005_02'));
ok($reporter->_is_a_perl_release('perl5.005_01'));
ok($reporter->_is_a_perl_release('perl5.005'));
ok($reporter->_is_a_perl_release('perl5.004_05'));
ok($reporter->_is_a_perl_release('perl5.004_04'));
ok($reporter->_is_a_perl_release('perl5.004_03'));
ok($reporter->_is_a_perl_release('perl5.004_02'));
ok($reporter->_is_a_perl_release('perl5.004_01'));
ok($reporter->_is_a_perl_release('perl5.004'));
ok($reporter->_is_a_perl_release('perl5.003_07'));
ok($reporter->_is_a_perl_release('perl-1.0_16'));
ok($reporter->_is_a_perl_release('perl-1.0_15'));
ok(not $reporter->_is_a_perl_release('Perl-BestPractice-0.01'));
ok(not $reporter->_is_a_perl_release('Perl-Compare-0.10'));
ok(not $reporter->_is_a_perl_release('Perl-Critic-0.2'));
ok(not $reporter->_is_a_perl_release('Perl-Dist-0.0.5'));
ok(not $reporter->_is_a_perl_release('Perl-Dist-Strawberry-0.1.2'));
ok(not $reporter->_is_a_perl_release('Perl-Dist-Vanilla-7'));
ok(not $reporter->_is_a_perl_release('Perl-Editor-0.02'));
ok(not $reporter->_is_a_perl_release('Perl-Editor-Plugin-Squish-0.01'));
ok(not $reporter->_is_a_perl_release('Perl-Metrics-0.06'));
ok(not $reporter->_is_a_perl_release('Perl-MinimumVersion-0.13'));
ok(not $reporter->_is_a_perl_release('Perl-Repository-APC-1.216'));
ok(not $reporter->_is_a_perl_release('Perl-SAX-0.07'));
ok(not $reporter->_is_a_perl_release('Perl-Signature-0.08'));
ok(not $reporter->_is_a_perl_release('Perl-Tags-0.23'));
ok(not $reporter->_is_a_perl_release('Perl-Tidy-20060719'));
ok(not $reporter->_is_a_perl_release('Perl-Squish-0.02'));
ok(not $reporter->_is_a_perl_release('Perl-Visualize-1.02'));

like($reporter->message_id, '/^<\d+\.[^.]+\.\d+@[^>]+>$/');

undef $reporter;

$reporter = Test::Reporter->new();
isa_ok($reporter, 'Test::Reporter');

is($reporter->transport(), 'Net::SMTP');
is($reporter->{_transport}, 'Net::SMTP');

undef $reporter;
$reporter = Test::Reporter->new();
isa_ok($reporter, 'Test::Reporter');
is($reporter->transport('Net::SMTP'), 'Net::SMTP');
is($reporter->{_transport}, 'Net::SMTP');

# Arguments stored in _tls
$reporter->transport('Net::SMTP', Username => 'LarryW', Password => 'JAPH');
my %tls_args = $reporter->transport_args();
is( $tls_args{Username}, 'LarryW' );
is( $tls_args{Password}, 'JAPH' );

eval { $reporter->transport('Invalid'); };
like($@, q{/could not load 'Test::Reporter::Transport::Invalid'/})
    or print "# $@\n";

{
    local $Test::Reporter::Send = 1;
    local $INC{"Mail/Send.pm"} = 1; # pretend we have Mail::Send
    my @xport_args = ('foo', 'bar', 'baz', 'wibble', 'plink!');
    my $xport_args = \@xport_args;
    is($reporter->transport('Mail::Send', $xport_args), 'Mail::Send');
    is( join(" ", $reporter->transport_args), 
        join(" ", @xport_args)
    );
}

undef $reporter;

$reporter = Test::Reporter->new(transport => 'Net::SMTP');
isa_ok($reporter, 'Test::Reporter');
is($reporter->transport, 'Net::SMTP');
is($reporter->{_transport}, 'Net::SMTP');
