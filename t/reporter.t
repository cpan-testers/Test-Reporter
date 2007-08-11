#!/usr/bin/perl -w

use strict;
use Test;
use Test::Reporter;

BEGIN { plan tests => 43 }

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
