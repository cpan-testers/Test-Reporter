use strict;
use warnings;
package Test::Reporter::Transport::Net::SMTP;
use base 'Test::Reporter::Transport';
use vars qw/$VERSION/;
$VERSION = '1.39_02';
$VERSION = eval $VERSION;

sub new {
    my ($class, @args) = @_;
    bless { args => \@args } => $class;
}

sub _net_class {
    my ($self) = @_;
    my $class = ref $self ? ref $self : $self;
    my ($net_class) =~ /^Test::Reporter::Transport::(.+)\z/;
    return $net_class;
}

sub _format_date {
    my ($self, $time) = @_;
    $time = time unless defined $time;

    my ($sec, $min, $hour, $mday, $mon, $year, $wday) = (localtime $time);
    my $day   = (qw[Sun Mon Tue Wed Thu Fri Sat])[$wday];
    my $month = (qw[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec])[$mon];
    $year += 1900;

    my ($direc, $tz_hr, $tz_mi) = $self->_tz_diff($time);

    sprintf "%s, %d %s %d %02d:%02d:%02d %s%02d%02d",
      $day, $mday, $month, $year, $hour, $min, $sec, $direc, $tz_hr, $tz_mi;
}

sub send {
    my ($self, $report, $recipients) = @_;
    $recipients ||= [];

    my $helo          = $report->_maildomain(); # XXX: tight -- rjbs, 2008-04-06
    my $from          = $report->from();
    my $via           = $report->via();
    my @tmprecipients = ();
    my @bad           = ();
    my $success       = 0;
    my $smtp;

    my $mx;

    my $transport = $self->_net_class;

    # Sorry.  Tight coupling happened before I got here. -- rjbs, 2008-04-06
    for my $server (@{$report->{_mx}}) {
        eval {
            $smtp = $transport->new(
                $server,
                Hello   => $helo,
                Timeout => $report->timeout(),
                Debug   => $report->debug(),
                $report->transport_args(),
            );
        };

        if (defined $smtp) {
            $mx = $server;
            last;
        }
    }

    die "Unable to connect to any MX's" unless $mx && $smtp;

    my $cc_str;
    if (@$recipients) {
        if ($mx =~ /(?:^|\.)(?:perl|cpan)\.org$/) {
            for my $recipient (sort @$recipients) {
                if ($recipient =~ /(?:@|\.)(?:perl|cpan)\.org$/) {
                    push @tmprecipients, $recipient;
                } else {
                    push @bad, $recipient;
                }
            }

            if (@bad) {
                warn __PACKAGE__, ": Will not attempt to cc the following recipients since perl.org MX's will not relay for them. Either use Test::Reporter::Transport::Mail::Send, use other MX's, or only cc address ending in cpan.org or perl.org: ${\(join ', ', @bad)}.\n";
            }

            $recipients = \@tmprecipients;
        }

        $cc_str = join ', ', @$recipients;
        chomp $cc_str;
        chomp $cc_str;
    }

    $via = ', via ' . $via if $via;

    my $envelope_sender = $from;
    $envelope_sender =~ s/\s\([^)]+\)$//; # email only; no name

    $success += $smtp->mail($envelope_sender);
    $success += $smtp->to($report->address);
    $success += $smtp->cc(@$recipients) if @$recipients;
    $success += $smtp->data();
    $success += $smtp->datasend("Date: ", $self->_format_date, "\n");
    $success += $smtp->datasend("Subject: ", $report->subject, "\n");
    $success += $smtp->datasend("From: $from\n");
    $success += $smtp->datasend("To: ", $self->address, "\n");
    $success += $smtp->datasend("Cc: $cc_str\n") if @$recipients && $success == 8;
    $success += $smtp->datasend("Message-ID: ", $report->message_id(), "\n");
    $success +=
        $smtp->datasend("X-Reported-Via: Test::Reporter $Test::Reporter::VERSION$via\n");
    $success += $smtp->datasend("\n");
    $success += $smtp->datasend($report->report());
    $success += $smtp->dataend();
    $success += $smtp->quit;

    if (@$recipients && $success != 15 ) {
        die "Unable to send test report to one or more recipients\n";
    }
    elsif ($success != 13) {
        die "Unable to send test report\n";
    }

    return 1;
}

1;
