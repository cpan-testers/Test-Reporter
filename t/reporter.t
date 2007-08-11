#!/usr/bin/perl -w

# TODO: use Test::More and add more tests

use strict;
use Test;
use Test::Reporter;

BEGIN { plan tests => 18 }

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

ok($reporter->subject =~ /^FAIL Foo-Bar-1.50\s/);
ok($reporter->report =~ /This distribution has been tested/);
ok($reporter->report =~ /Please cc any replies to/);
ok($reporter->report =~ /Summary of my/);
ok($reporter->report =~ /blah/);
ok($reporter->grade, 'fail');
ok($reporter->distribution, 'Foo-Bar-1.50');
ok($reporter->timeout, 60);
ok($reporter->comments, 'blah');
