#!/usr/bin/perl -w

use strict;
use Test::More;
use File::Temp;
use File::Find;

#--------------------------------------------------------------------------#

my $from = 'johndoe@example.net';
my $dir = File::Temp::tempdir( CLEANUP => 1 );

#--------------------------------------------------------------------------#

plan tests => 4;

require_ok( 'Test::Reporter' );

my $reporter = Test::Reporter->new();
ok(ref $reporter, 'Test::Reporter');

$reporter->grade('pass');
$reporter->distribution('Mail-Freshmeat-1.20');
$reporter->from($from);

my $form = {
    key     => 123456789,
    via     => my $via = "Test::Reporter ${Test::Reporter::VERSION}",
    from    => $from,
    subject => $reporter->subject(),
    report  => $reporter->report(),
};

$reporter->transport("File", $dir);

eval { $reporter->send };
is( $@, "", "report sent ok" );

my @reports;
find( sub { 
    push @reports, $_ if -f; 
}, $dir );

is( scalar @reports, 1, "found a report in the directory" );

