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
    my ($net_class) = ($class =~ /^Test::Reporter::Transport::(.+)\z/);
    return $net_class;
}

# Next two subs courtesy of Casey West, Ricardo SIGNES, and Email::Date
# Visit the Perl Email Project at: http://emailproject.perl.org/
sub _tz_diff {
    my ($self, $time) = @_;

    my $diff  =   Time::Local::timegm(localtime $time)
                - Time::Local::timegm(gmtime    $time);

    my $direc = $diff < 0 ? '-' : '+';
       $diff  = abs $diff;
    my $tz_hr = int( $diff / 3600 );
    my $tz_mi = int( $diff / 60 - $tz_hr * 60 );

    return ($direc, $tz_hr, $tz_mi);
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

    die "Unable to connect to any MX's: $@" unless $mx && $smtp;

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

    # Net::SMTP returns 1 or undef for pass/fail 
    # Net::SMTP::TLS croaks on fail but may not return 1 on pass
    # so this closure lets us die on an undef return only for Net::SMTP
    my $die = sub { die $smtp->message if ref $smtp eq 'Net::SMTP' };
    
    eval {
        $smtp->mail($envelope_sender) or $die->();
        $smtp->to($report->address) or $die->();
        if ( @$recipients ) { $smtp->cc(@$recipients) or $die->() };
        $smtp->data() or $die->();
        $smtp->datasend("Date: ", $self->_format_date, "\n") or $die->();
        $smtp->datasend("Subject: ", $report->subject, "\n") or $die->();
        $smtp->datasend("From: $from\n") or $die->();
        $smtp->datasend("To: ", $report->address, "\n") or $die->();
        if ( @$recipients ) { $smtp->datasend("Cc: $cc_str\n") or $die->() };
        $smtp->datasend("Message-ID: ", $report->message_id(), "\n") or $die->();
        $smtp->datasend("X-Reported-Via: Test::Reporter $Test::Reporter::VERSION$via\n") or $die->();
        $smtp->datasend("\n") or $die->();
        $smtp->datasend($report->report()) or $die->();
        $smtp->dataend() or $die->();
        $smtp->quit or $die->();
    };
    if ($@) { 
        die "$transport: " . $smtp->message;
    }

    return 1;
}

1;
