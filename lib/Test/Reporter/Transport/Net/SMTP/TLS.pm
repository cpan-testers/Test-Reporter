use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }
package Test::Reporter::Transport::Net::SMTP::TLS;
# ABSTRACT: Authenticated SMTP transport for Test::Reporter

use base 'Test::Reporter::Transport::Net::SMTP';

use Net::SMTP::TLS;

1;

__END__

=head1 SYNOPSIS

    my $report = Test::Reporter->new(
        transport => 'Net::SMTP::TLS',
        transport_args => [ User => 'Joe', Password => '123' ],
    );

=head1 DESCRIPTION

This module transmits a Test::Reporter report using Net::SMTP::TLS.

=head1 USAGE

See L<Test::Reporter> and L<Test::Reporter::Transport> for general usage
information.

=head2 Transport Arguments

    $report->transport_args( @args );

Any transport arguments are passed through to the Net::SMTP::TLS constructer.

=head1 METHODS

These methods are only for internal use by Test::Reporter.

=head2 new

    my $sender = Test::Reporter::Transport::Net::SMTP::TLS->new( 
        @args 
    );
    
The C<new> method is the object constructor.   

=head2 send

    $sender->send( $report );

The C<send> method transmits the report.  

=cut

