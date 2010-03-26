#!/usr/bin/perl -w

use strict;
use Test::More;

$Test::Reporter::VERSION ||= 999; # dzil will set it for us on release

# hack-mock Net::SMTP
BEGIN {
    $INC{"Net/SMTP.pm"} = 1;
    package Net::SMTP;
    sub new { return bless {} }
    use vars qw/$AUTOLOAD $Response %Data/;
    $Response = 1;
    sub data { 1 }
    sub dataend { 1 }
    sub quit { return $Response }
    sub AUTOLOAD {
        my $self = shift;
        (my $method = $AUTOLOAD) =~ s{^Net::SMTP::}{};
        if ( @_ ) { push @{ $Data{ $method } }, @_ }
        return 1;
    }
    
}

#--------------------------------------------------------------------------#

my $from = 'johndoe@example.net';

#--------------------------------------------------------------------------#

plan tests => 5;

require_ok( 'Test::Reporter' );

#--------------------------------------------------------------------------#
# simple test
#--------------------------------------------------------------------------#

my $reporter = Test::Reporter->new();
isa_ok($reporter, 'Test::Reporter');

$reporter->grade('pass');
$reporter->distribution('Mail-Freshmeat-1.20');
$reporter->distfile('ASPIERS/Mail-Freshmeat-1.20.tar.gz');
$reporter->from($from);

my $form = {
    via     => my $via = "Test::Reporter ${Test::Reporter::VERSION}",
    from    => $from,
    subject => $reporter->subject(),
    report  => $reporter->report(),
};

{
    local $Net::SMTP::Data;
    my $rc = $reporter->send;
    ok( $rc, "send() is true when successful" ) or diag $reporter->errstr;
    ok( ( grep { /X-Test-Reporter-Perl: v5\.\d+\.\d+/ } @{$Net::SMTP::Data{datasend}}),
      "saw X-Test-Reporter-Perl header"
    );

}

{
    local $Net::SMTP::Data;
    local $Net::SMTP::Response = 0; # ok
    my $rc = $reporter->send;
    ok( ! $rc, "send() false on failure" ) or diag $reporter->errstr;
}

#--------------------------------------------------------------------------#
# test specifying arguments in the constructor
#--------------------------------------------------------------------------#
#
#my $transport_args = [$url, $form->{key}];
#
#$reporter = Test::Reporter->new(
#  transport => "HTTPGateway",
#  transport_args => $transport_args,
#);
#isa_ok($reporter, 'Test::Reporter');
#
#is_deeply( [ $reporter->transport_args ], $transport_args,
#  "transport_args set correctly by new()"
#);
