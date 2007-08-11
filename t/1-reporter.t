#!/usr/bin/perl -w

# $Id: 1-reporter.t 67 2007-06-27 17:57:42Z afoxson $
# $HeadURL: https://test-reporter.googlecode.com/svn/branches/1.30/t/1-reporter.t $

use strict;
use FileHandle;
use Test;
use Test::Reporter;

BEGIN { plan tests => 116 }

my $distro = sprintf "Test-Reporter-%s", $Test::Reporter::VERSION;

my $reporter = Test::Reporter->new();
ok(ref $reporter, 'Test::Reporter');

$reporter->grade('pass');
$reporter->distribution('Mail-Freshmeat-1.20');

ok($reporter->subject =~ /^PASS Mail-Freshmeat-1.20\s/);
ok($reporter->report =~ /This distribution has been tested/);
ok($reporter->report =~ /Please cc any replies to/);
ok($reporter->report =~ /Summary of my/);
ok($reporter->grade, 'pass');
ok($reporter->distribution, 'Mail-Freshmeat-1.20');
ok($reporter->timeout, 120);

undef $reporter;

$reporter = Test::Reporter->new();
ok(ref $reporter, 'Test::Reporter');

$reporter->grade('fail');
$reporter->distribution('Foo-Bar-1.50');
$reporter->comments('blah');
$reporter->timeout(60);
$reporter->via('CPANPLUS');
$reporter->from('foo@bar.com');
$reporter->address('send@reports.here');
$reporter->mx([1, 2, 3, 4, 5, 6, 7, 8, 9]);

ok($reporter->subject =~ /^FAIL Foo-Bar-1.50\s/);
ok($reporter->report =~ /This distribution has been tested/);
ok($reporter->report =~ /Please cc any replies to/);
ok($reporter->report =~ /Summary of my/);
ok($reporter->report =~ /blah/);
ok($reporter->grade, 'fail');
ok($reporter->distribution, 'Foo-Bar-1.50');
ok($reporter->timeout, 60);
ok($reporter->comments, 'blah');
ok($reporter->via, 'CPANPLUS');
ok($reporter->from, 'foo@bar.com');
ok($reporter->address, 'send@reports.here');
ok($reporter->debug, 0);
ok(scalar @{$reporter->mx}, 9);

undef $reporter;

$reporter = Test::Reporter->new();
ok(ref $reporter, 'Test::Reporter');

$reporter->grade('na');
ok($reporter->grade, 'na');
ok($reporter->timeout, 120);

undef $reporter;

$reporter = Test::Reporter->new();
ok(ref $reporter, 'Test::Reporter');

$reporter->grade('unknown');
ok($reporter->grade, 'unknown');

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
ok(ref $reporter, 'Test::Reporter');
ok($reporter->subject =~ /^PASS Bar-1.0\s/);
ok($reporter->report =~ /This distribution has been tested/);
ok($reporter->report =~ /Please cc any replies to/);
ok($reporter->report =~ /Summary of my/);
ok($reporter->report =~ /woo/);
ok($reporter->grade, 'pass');
ok($reporter->distribution, 'Bar-1.0');
ok($reporter->timeout, 500);
ok($reporter->comments, 'woo');
ok($reporter->via, 'something');
ok($reporter->from, 'me@me.com');
ok($reporter->address, 'foo@bar');
ok($reporter->debug, 0);
ok(scalar @{$reporter->mx}, 5);
ok($reporter->dir, '/tmp');

# ---

undef $reporter;

$reporter = Test::Reporter->new
(
    grade => 'pass',
    distribution => $distro,
);
ok(ref $reporter, 'Test::Reporter');
my $file = $reporter->write();
ok($file =~ /Test-Reporter/);
ok(-e $file);

undef $reporter;

$reporter = Test::Reporter->new
(
)->read($file);
ok(ref $reporter, 'Test::Reporter');
ok($reporter->subject =~ /^PASS $distro\s/);
ok($reporter->report =~ /This distribution has been tested/);
ok($reporter->report =~ /Please cc any replies to/);
ok($reporter->report =~ /Summary of my/);
ok($reporter->grade, 'pass');
ok($reporter->distribution, $distro);

# testing perl-version with the current perl
my $alt_perl = 'alt_perl.pl';
my $no_version = $reporter->perl_version;
my $same_version = $reporter->perl_version($^X);
for my $field ( qw( _archname _osvers _myconfig) )
  { ok( $no_version->{$field} eq $same_version->{$field}); }

# testing perl-version with a fake perl
# create fake perl
{
    my $fh = FileHandle->new();
    open( $fh, '>', $alt_perl) or die "cannot create (fake) $alt_perl: $!";
    # fake perl, still needs to grab the magick number!
    print {$fh} qq{(\$m= join( '', \@ARGV))=~ s{\\D}{}g; print "\$m\nnew_archname\nnew_osvers\nnew_myconfig\n(several lines)"; };
    close $fh;

    my $alt_perl_version = $reporter->perl_version("$^X $alt_perl");
    ok( $reporter->perl_version->{_archname} eq 'new_archname');
    ok( $reporter->perl_version->{_osvers} eq 'new_osvers');
    ok( $reporter->perl_version->{_myconfig} eq "new_myconfig\n(several lines)");

    unlink $alt_perl;
}

# testing error
{
    my $fh = FileHandle->new();
    open( $fh, '>', $alt_perl) or die "cannot create (fake, not working) $alt_perl: $!";
    # fake perl, gives wrong output
    print {$fh} qq{print "booh"; };
    close $fh;

    eval { $reporter->perl_version( "$^X $alt_perl"); };
    ok($@=~ q{^Test::Reporter: cannot get perl version info from});
    unlink $alt_perl;
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

ok($reporter->message_id =~ /^<\d+\.[^.]+\.\d+@[^>]+>$/);
