#!/usr/bin/perl -w

use strict;
use FileHandle;
use Test::More 'no_plan';
use Test::Reporter;


my $reporter = Test::Reporter->new();
ok(ref $reporter, 'Test::Reporter');

$reporter->grade('pass');
$reporter->distribution('Mail-Freshmeat-1.20');
$reporter->transport('HTTP','url','key');
$reporter->send;

