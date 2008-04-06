use strict;
use warnings;
package Test::Reporter::Transport::Mail::Send;
use base 'Test::Reporter::Transport';
use vars qw/$VERSION/;
$VERSION = '1.39_02';
$VERSION = eval $VERSION;

use Mail::Send;

sub new {
    my ($class, @args) = @_;
    bless { args => \@args } => $class;
}

sub send {
    my ($self, $report, $recipients) = @_;
    $recipients ||= [];

    my $via = $report->via();
    my $msg = Mail::Send->new();

    my $cc_str;
    if (@$recipients) {
        $cc_str = join ', ', @$recipients;
        chomp $recipients;
        chomp $recipients;
    }

    $via = ', via ' . $via if $via;

    $msg->to($report->address());
    $msg->set('From', $report->from());
    $msg->subject($report->subject());
    $msg->add('X-Reported-Via', "Test::Reporter $Test::Reporter::VERSION$via");
    $msg->add('Cc', $recipients) if @_;

    my $fh = $msg->open( @{ $self->{args} } );

    print $fh $self->report();
    
    $fh->close();
}

1;
