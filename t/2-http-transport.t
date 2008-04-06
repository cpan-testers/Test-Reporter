#!/usr/bin/perl -w

use strict;
use Test::More;

# hack-mock LWP::UserAgent
BEGIN {
    $INC{"LWP/UserAgent.pm"} = 1;
    package LWP::UserAgent;
    sub new { return bless {} }
    use vars qw/$AUTOLOAD $Args $Url/;
    sub post {
        my $self = shift;
        ($Url, $Args) = @_;
        return bless {}, "HTTP::Response";
    }

    sub AUTOLOAD {
        my $self = shift;
        if ( @_ ) { $self->{ $AUTOLOAD } = shift }
        return $self->{ $AUTOLOAD };
    }
    
    $INC{"HTTP/Response.pm"} = 1;
    package HTTP::Response;
    use vars qw/$AUTOLOAD $Result/;
    sub is_success { $Result };
    sub status_line { '400' };
    sub content { $Result ? "OK" : 'Major error' };
    sub AUTOLOAD {
        my $self = shift;
        if ( @_ ) { $self->{ $AUTOLOAD } = shift }
        return $self->{ $AUTOLOAD };
    }
    
}

#--------------------------------------------------------------------------#

my $url = "http://example.com/";
my $from = 'johndoe@example.net';

#--------------------------------------------------------------------------#

plan tests => 6;

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

$reporter->transport("HTTPGateway", $url, $form->{key});

{
    local $LWP::UserAgent::Args;
    local $HTTP::Response::Result = 1; # ok
    my $rc = $reporter->send;
    is( $LWP::UserAgent::Url, $url, "POST url appears correct" );
    is_deeply( $LWP::UserAgent::Args, $form, "POST data appears correct"); 
    ok( $rc, "send() is true when successful" );
}

{
    local $LWP::UserAgent::Args;
    local $HTTP::Response::Result = 0; # ok
    my $rc = $reporter->send;
    ok( ! $rc, "send() false on failure" );
}
