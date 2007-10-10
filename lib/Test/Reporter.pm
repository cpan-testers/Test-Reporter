# Test::Reporter - sends test results to cpan-testers@perl.org
# Copyright (c) 2007 Adam J. Foxson. All rights reserved.

# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package Test::Reporter;

use strict;
use Cwd;
use Config;
use Carp;
use Net::SMTP;
use FileHandle;
use File::Temp;
use Sys::Hostname;
use Time::Local ();
use vars qw($VERSION $AUTOLOAD $Tempfile $Report $DNS $Domain $Send);
use constant FAKE_NO_NET_DNS => 0;    # for debugging only
use constant FAKE_NO_NET_DOMAIN => 0; # for debugging only
use constant FAKE_NO_MAIL_SEND => 0;  # for debugging only

$VERSION = '1.38';

local $^W = 1;

sub new {
    my $type  = shift;
    my $class = ref($type) || $type;
    my $self  = {
        '_mx'                => ['mx.develooper.com'],
        '_address'           => 'cpan-testers@perl.org',
        '_grade'             => undef,
        '_distribution'      => undef,
        '_report'            => undef,
        '_subject'           => undef,
        '_from'              => undef,
        '_comments'          => '',
        '_errstr'            => '',
        '_via'               => '',
        '_mail_send_args'    => '',
        '_timeout'           => 120,
        '_debug'             => 0,
        '_dir'               => '',
        '_subject_lock'      => 0,
        '_report_lock'       => 0,
        '_perl_version'      => {
            '_archname' => $Config{archname},
            '_osvers'   => $Config{osvers},
            '_myconfig' => Config::myconfig(),
        },
        '_transport'         => '',
    };

    bless $self, $class;

    $self->{_attr} = {   
        map {$_ => 1} qw(   
            _address _distribution _comments _errstr _via _timeout _debug _dir
        )
    };

    warn __PACKAGE__, ": new\n" if $self->debug();
    croak __PACKAGE__, ": new: even number of named arguments required"
        unless scalar @_ % 2 == 0;

    $self->_process_params(@_) if @_;
    $self->_get_mx(@_) if $self->_have_net_dns();

    return $self;
}

sub _get_mx {
    my $self = shift;
    warn __PACKAGE__, ": _get_mx\n" if $self->debug();

    my %params = @_;

    return if exists $params{'mx'};

    my $dom = $params{'address'} || $self->address();
    my @mx;

    $dom =~ s/^.+\@//;

    for my $mx (sort {$a->preference() <=> $b->preference()} Net::DNS::mx($dom)) {
        push @mx, $mx->exchange();
    }

    if (not @mx) {
        warn __PACKAGE__,
            ": _get_mx: unable to find MX's for $dom, using defaults\n" if
                $self->debug();
        return;
    }

    $self->mx(\@mx);
}

sub _process_params {
    my $self = shift;
    warn __PACKAGE__, ": _process_params\n" if $self->debug();

    my %params   = @_;
    my @defaults = qw(
        mx address grade distribution from comments via timeout debug dir perl_version transport);
    my %defaults = map {$_ => 1} @defaults;

    for my $param (keys %params) {   
        croak __PACKAGE__, ": new: parameter '$param' is invalid." unless
            exists $defaults{$param};
    }

    for my $param (keys %params) {   
        $self->$param($params{$param});
    }
}

sub subject {
    my $self = shift;
    warn __PACKAGE__, ": subject\n" if $self->debug();
    croak __PACKAGE__, ": subject: grade and distribution must first be set"
        if not defined $self->{_grade} or not defined $self->{_distribution};

    return $self->{_subject} if $self->{_subject_lock};

    my $subject = uc($self->{_grade}) . ' ' . $self->{_distribution} .
        " $self->{_perl_version}->{_archname} $self->{_perl_version}->{_osvers}";

    return $self->{_subject} = $subject;
}

sub report {
    my $self = shift;
    warn __PACKAGE__, ": report\n" if $self->debug();

    return $self->{_report} if $self->{_report_lock};

    my $report;
    $report .= "This distribution has been tested as part of the cpan-testers\n";
    $report .= "effort to test as many new uploads to CPAN as possible.  See\n";
    $report .= "http://testers.cpan.org/\n\n";
    $report .= "Please cc any replies to cpan-testers\@perl.org to keep other\n";
    $report .= "test volunteers informed and to prevent any duplicate effort.\n";

    if (not $self->{_comments}) {
        $report .= "\n\n--\n\n";
    }
    else {
        $report .= "\n--\n" . $self->{_comments} . "\n--\n\n";
    }

    $report .= $self->{_perl_version}->{_myconfig};

    chomp $report;
    chomp $report;

    return $self->{_report} = $report;
}

sub grade {
    my ($self, $grade) = @_;
    warn __PACKAGE__, ": grade\n" if $self->debug();

    my %grades    = (
        'pass'    => "all tests passed",
        'fail'    => "one or more tests failed",
        'na'      => "distribution will not work on this platform",
        'unknown' => "distribution did not include tests",
    );

    return $self->{_grade} if scalar @_ == 1;

    croak __PACKAGE__, ":grade: '$grade' is invalid, choose from: " .
        join ' ', keys %grades unless $grades{$grade};

    return $self->{_grade} = $grade;
}

sub transport {
    my $self = shift;
    warn __PACKAGE__, ": transport\n" if $self->debug();

    my %transports    = (
        # support for plugin transports will eventually be added, but not today
        'Net::SMTP' => 'Builtin transport using Net::SMTP',
        'Mail::Send' => 'Builtin transport using Mail::Send',
    );

    return $self->{_transport} unless scalar @_;

    my $transport = shift;

    croak __PACKAGE__, ":transport: '$transport' is invalid, choose from: " .
        join ' ', keys %transports unless $transports{$transport};

    my $args = shift;

    if ($transport eq 'Mail::Send' && defined $args && ref $args eq 'ARRAY') {
        $self->mail_send_args($args);
    }

    return $self->{_transport} = $transport;
}

sub edit_comments {
    my($self, %args) = @_;
    warn __PACKAGE__, ": edit_comments\n" if $self->debug();

    my %tempfile_args = (
        UNLINK => 1,
        SUFFIX => '.txt',
    );

    if (exists $args{'suffix'} && defined $args{'suffix'} && length $args{'suffix'}) {
        $tempfile_args{SUFFIX} = $args{'suffix'};
        # prefix the extension with a period, if the user didn't.
        $tempfile_args{SUFFIX} =~ s/^(?!\.)(?=.)/./;
    }

    ($Tempfile, $Report) = File::Temp::tempfile(%tempfile_args);

    print $Tempfile $self->{_comments};

    $self->_start_editor();

    my $comments;
    {
        local $/;
        open FH, $Report or die __PACKAGE__, ": Can't open comment file '$Report': $!";
        $comments = <FH>;
        close FH or die __PACKAGE__, ": Can't close comment file '$Report': $!";
    }

    chomp $comments;

    $self->{_comments} = $comments;

    return;
}

sub send {
    my ($self, @recipients) = @_;
    warn __PACKAGE__, ": send\n" if $self->debug();

    $self->from();
    $self->report();
    $self->subject();

    return unless $self->_verify();

    if ($self->_is_a_perl_release($self->distribution())) {
        $self->errstr(__PACKAGE__ . ": use perlbug for reporting test " .
            "results against perl itself");
        return;
    }

    my $transport = $self->transport();

    if ($transport eq 'Mail::Send' && $self->_have_mail_send()) {
        return $self->_mail_send(@recipients);
    }
    elsif ($transport eq 'Net::SMTP') {
        return $self->_send_smtp(@recipients);
    }
    else {
        # Addresses #9831: Usage of Mail::Mailer is broken on Win32
        if ($^O !~ /^(?:cygwin|MSWin32|VMS)$/ && $self->_have_mail_send()) {
            return $self->_mail_send(@recipients);
        }
        else {
            return $self->_send_smtp(@recipients);
        }
    }
}

sub write {
    my $self = shift;
    warn __PACKAGE__, ": write\n" if $self->debug();

    my $from = $self->from();
    my $report = $self->report();
    my $subject = $self->subject();
    my $distribution = $self->distribution();
    my $grade = $self->grade();
    my $dir = $self->dir() || cwd;

    return unless $self->_verify();

    $distribution =~ s/[^A-Za-z0-9\.\-]+//g;

    my($fh, $file); unless ($fh = $_[0]) {
        $file = "$grade.$distribution.$self->{_perl_version}->{_archname}.$self->{_perl_version}->{_osvers}.${\(time)}.$$.rpt";

        if ($^O eq 'VMS') {
            $file = "$grade.$distribution.$self->{_perl_version}->{_archname}";
            my $ext = "$self->{_perl_version}->{_osvers}.${\(time)}.$$.rpt";
            # only 1 period in filename
            # we also only have 39.39 for filename
            $file =~ s/\./_/g;
            $ext  =~ s/\./_/g;
            $file = $file . '.' . $ext;
        }

        $file = File::Spec->catfile($dir, $file);

        warn $file if $self->debug();
        $fh = FileHandle->new();
        open $fh, ">$file" or die __PACKAGE__, ": Can't open report file '$file': $!";
    }
    print $fh "From: $from\n";
    print $fh "Subject: $subject\n";
    print $fh "Report: $report";
    unless ($_[0]) {
        close $fh or die __PACKAGE__, ": Can't close report file '$file': $!";
        warn $file if $self->debug();
        return $file;
    } else {
        return $fh;
    }
}

sub read {
    my ($self, $file) = @_;
    warn __PACKAGE__, ": read\n" if $self->debug();

    my $buffer;

    {
        local $/;
        open REPORT, $file or die __PACKAGE__, ": Can't open report file '$file': $!";
        $buffer = <REPORT>;
        close REPORT or die __PACKAGE__, ": Can't close report file '$file': $!";
    }

    if (my ($from, $subject, $report) = $buffer =~ /^From:\s(.+)Subject:\s(.+)Report:\s(.+)$/s) {
        my ($grade, $distribution) = (split /\s/, $subject)[0,1];
        $self->from($from) unless $self->from();
        $self->{_subject} = $subject;
        $self->{_report} = $report;
        $self->{_grade} = lc $grade;
        $self->{_distribution} = $distribution;
        $self->{_subject_lock} = 1;
        $self->{_report_lock} = 1;
    } else {
        die __PACKAGE__, ": Failed to parse report file '$file'\n";
    }

    return $self;
}

sub _verify {
    my $self = shift;
    warn __PACKAGE__, ": _verify\n" if $self->debug();

    my @undefined;

    for my $key (keys %{$self}) {
        push @undefined, $key unless defined $self->{$key};
    }

    $self->errstr(__PACKAGE__ . ": Missing values for: " .
        join ', ', map {$_ =~ /^_(.+)$/} @undefined) if
        scalar @undefined > 0;
    return $self->errstr() ? return 0 : return 1;
}

sub _mail_send {
    my $self = shift;
    warn __PACKAGE__, ": _mail_send\n" if $self->debug();

    my $fh;
    my $recipients;
    my @recipients = @_;
    my $via        = $self->via();
    my $msg        = Mail::Send->new();

    if (@recipients) {
        $recipients = join ', ', @recipients;
        chomp $recipients;
        chomp $recipients;
    }

    $via = ', via ' . $via if $via;

    $msg->to($self->address());
    $msg->set('From', $self->from());
    $msg->subject($self->subject());
    $msg->add('X-Reported-Via', "Test::Reporter ${VERSION}$via");
    $msg->add('Cc', $recipients) if @_;

    if ($self->mail_send_args() and ref $self->mail_send_args() eq 'ARRAY') {
        $fh = $msg->open(@{$self->mail_send_args()});
    }
    else {
        $fh = $msg->open();
    }

    print $fh $self->report();
    
    $fh->close();
}

sub _send_smtp {
    my $self = shift;
    warn __PACKAGE__, ": _send_smtp\n" if $self->debug();

    my $helo          = $self->_maildomain();
    my $from          = $self->from();
    my $via           = $self->via();
    my $debug         = $self->debug();
    my @recipients    = @_;
    my @tmprecipients = ();
    my @bad           = ();
    my $success       = 0;
    my $fail          = 0;
    my $recipients;
    my $smtp;

    my $mx;
    for my $server (@{$self->{_mx}}) {
        $smtp = Net::SMTP->new($server, Hello => $helo,
            Timeout => $self->{_timeout}, Debug => $debug);

        if (defined $smtp) {
            $mx = $server;
            last;
        }
        else {
            warn __PACKAGE__, ": Unable to connect to MX '$server'\n" if $self->debug();
            $fail++;
        }
    }

    unless ($mx && $smtp) {
        $self->errstr(__PACKAGE__ . ': Unable to connect to any MX\'s');
        return 0;
    }

    if (@recipients) {
        if ($mx =~ /(?:^|\.)(?:perl|cpan)\.org$/) {
            for my $recipient (sort @recipients) {
                if ($recipient =~ /(?:@|\.)(?:perl|cpan)\.org$/) {
                    push @tmprecipients, $recipient;
                } else {
                    push @bad, $recipient;
                }
            }

            if (@bad) {
                warn __PACKAGE__, ": Will not attempt to cc the following recipients since perl.org MX's will not relay for them. Either install Mail::Send, use other MX's, or only cc address ending in cpan.org or perl.org: ${\(join ', ', @bad)}.\n";
            }

            @recipients = @tmprecipients;
        }

        $recipients = join ', ', @recipients;
        chomp $recipients;
        chomp $recipients;
    }

    $via = ', via ' . $via if $via;

    my $envelope_sender = $from;
    $envelope_sender =~ s/\s\([^)]+\)$//; # email only; no name

    $success += $smtp->mail($envelope_sender);
    $success += $smtp->to($self->{_address});
    $success += $smtp->cc(@recipients) if @recipients;
    $success += $smtp->data();
    $success += $smtp->datasend("Date: ", $self->_format_date, "\n");
    $success += $smtp->datasend("Subject: ", $self->subject(), "\n");
    $success += $smtp->datasend("From: $from\n");
    $success += $smtp->datasend("To: ", $self->{_address}, "\n");
    $success += $smtp->datasend("Cc: $recipients\n") if @recipients && $success == 8;
    $success += $smtp->datasend("Message-ID: ", $self->message_id(), "\n");
    $success +=
        $smtp->datasend("X-Reported-Via: Test::Reporter ${VERSION}$via\n");
    $success += $smtp->datasend("\n");
    $success += $smtp->datasend($self->report());
    $success += $smtp->dataend();
    $success += $smtp->quit;

    if (@recipients) {
        $self->errstr(__PACKAGE__ .
            ": Unable to send test report to one or more recipients\n") if $success != 15;
    }
    else {
        $self->errstr(__PACKAGE__ . ": Unable to send test report\n") if $success != 13;
    }

    return $self->errstr() ? 0 : 1;
}

# Courtesy of Email::MessageID
sub message_id {
    my $self = shift;
    warn __PACKAGE__, ": message_id\n" if $self->debug();

    my $unique_value = 0;
    my @CHARS = ('A'..'F','a'..'f',0..9);
    my $length = 3;

    $length = rand(8) until $length > 3;

    my $pseudo_random = join '', (map $CHARS[rand $#CHARS], 0 .. $length), $unique_value++;
    my $user = join '.', time, $pseudo_random, $$;

    return '<' . $user . '@' . Sys::Hostname::hostname() . '>';
}

sub from {
    my $self = shift;
    warn __PACKAGE__, ": from\n" if $self->debug();

    if (@_) {
        $self->{_from} = shift;
        return $self->{_from};
    }
    else {
        return $self->{_from} if defined $self->{_from} and $self->{_from};
        $self->{_from} = $self->_mailaddress();
        return $self->{_from};
    }

}

sub mx {
    my $self = shift;
    warn __PACKAGE__, ": mx\n" if $self->debug();

    if (@_) {
        my $mx = shift;
        croak __PACKAGE__,
            ": mx: array reference required" if ref $mx ne 'ARRAY';
        $self->{_mx} = $mx;
    }

    return $self->{_mx};
}

sub mail_send_args {
    my $self = shift;
    warn __PACKAGE__, ": mail_send_args\n" if $self->debug();
    croak __PACKAGE__, ": mail_send_args cannot be called unless Mail::Send is installed\n" unless $self->_have_mail_send();

    if (@_) {
        my $mail_send_args = shift;
        croak __PACKAGE__, ": mail_send_args: array reference required" if
            ref $mail_send_args ne 'ARRAY';
        $self->{_mail_send_args} = $mail_send_args;
    }

    return $self->{_mail_send_args};
}

sub perl_version  {
    my $self = shift;
    warn __PACKAGE__, ": perl_version\n" if $self->debug();

    if( @_) {
        my $perl = shift;
        my $q = ( ($^O eq "MSWin32") || ($^O eq 'VMS') ) ? '"' : "'"; # quote for command-line perl
        my $magick = int(rand(1000));                                 # just to check that we get a valid result back
        my $cmd  = "$perl -MConfig -e$q print qq{$magick\n\$Config{archname}\n\$Config{osvers}\n},Config::myconfig();$q";
        if($^O eq 'VMS'){
            my $sh = $Config{'sh'};
            $cmd  = "$sh $perl $q-MConfig$q -e$q print qq{$magick\\n\$Config{archname}\\n\$Config{osvers}\\n},Config::myconfig();$q";
        }
        my $conf = `$cmd`;
        my %conf;
        ( @conf{ qw( magick _archname _osvers _myconfig) } ) = split( /\n/, $conf, 4);
        croak __PACKAGE__, ": cannot get perl version info from $perl: $conf" if( $conf{magick} ne $magick);
        delete $conf{magick};
        $self->{_perl_version} = \%conf;
   }
   return $self->{_perl_version};
}

sub AUTOLOAD {
    my $self               = $_[0];
    my ($package, $method) = ($AUTOLOAD =~ /(.*)::(.*)/);

    return if $method =~ /^DESTROY$/;

    unless ($self->{_attr}->{"_$method"}) {
        croak __PACKAGE__, ": No such method: $method; aborting";
    }

    my $code = q{
        sub {   
            my $self = shift;
            warn __PACKAGE__, ": METHOD\n" if $self->{_debug};
            $self->{_METHOD} = shift if @_;
            return $self->{_METHOD};
        }
    };

    $code =~ s/METHOD/$method/g;

    {
        no strict 'refs';
        *$AUTOLOAD = eval $code;
    }

    goto &$AUTOLOAD;
}

sub _have_net_dns {
    my $self = shift;
    warn __PACKAGE__, ": _have_net_dns\n" if $self->debug();

    return $DNS if defined $DNS;
    return 0 if FAKE_NO_NET_DNS;

    $DNS = eval {require Net::DNS};
}

sub _have_net_domain {
    my $self = shift;
    warn __PACKAGE__, ": _have_net_domain\n" if $self->debug();

    return $Domain if defined $Domain;
    return 0 if FAKE_NO_NET_DOMAIN;

    $Domain = eval {require Net::Domain};
}

sub _have_mail_send {
    my $self = shift;
    warn __PACKAGE__, ": _have_mail_send\n" if $self->debug();

    return $Send if defined $Send;
    return 0 if FAKE_NO_MAIL_SEND;

    $Send = eval {require Mail::Send};
}

sub _start_editor {
    my $self = shift;
    warn __PACKAGE__, ": _start_editor\n" if $self->debug();

    my $editor = $ENV{VISUAL} || $ENV{EDITOR} || $ENV{EDIT}
        || ($^O eq 'VMS'     and "edit/tpu")
        || ($^O eq 'MSWin32' and "notepad")
        || 'vi';

    $editor = $self->_prompt('Editor', $editor);

    die __PACKAGE__, ": The editor `$editor' could not be run" if system "$editor $Report";
    die __PACKAGE__, ": Report has disappeared; terminated" unless -e $Report;
    die __PACKAGE__, ": Empty report; terminated" unless -s $Report > 2;
}

sub _prompt {
    my $self = shift;
    warn __PACKAGE__, ": _prompt\n" if $self->debug();

    my ($label, $default) = @_;

    printf "$label%s", (" [$default]: ");
    my $input = scalar <STDIN>;
    chomp $input;

    return (length $input) ? $input : $default;
}

# From Mail::Util 1.74 (c) 1995-2001 Graham Barr (c) 2002-2005 Mark Overmeer
sub _maildomain {
    my $self = shift;
    warn __PACKAGE__, ": _maildomain\n" if $self->debug();

    my $domain = $ENV{MAILDOMAIN};

    return $domain if defined $domain;

    local *CF;
    local $_;

    my @sendmailcf = qw(
        /etc /etc/sendmail /etc/ucblib /etc/mail /usr/lib /var/adm/sendmail
    );

    my $config = (grep(-r, map("$_/sendmail.cf", @sendmailcf)))[0];

    if (defined $config && open(CF, $config)) {
        my %var;
        while (<CF>) {
            if (my ($v, $arg) = /^D([a-zA-Z])([\w.\$\-]+)/) {
                $arg =~ s/\$([a-zA-Z])/exists $var{$1} ? $var{$1} : '$'.$1/eg;
                $var{$v} = $arg;
            }
        }
        close(CF) || die $!;
        $domain = $var{j} if defined $var{j};
        $domain = $var{M} if defined $var{M};

        $domain = $1
            if ($domain && $domain =~ m/([A-Za-z0-9](?:[\.\-A-Za-z0-9]+))/);

        undef $domain if $^O eq 'darwin' && $domain =~ /\.local$/;

        return $domain if (defined $domain && $domain !~ /\$/);
    }

    if (open(CF, "/usr/lib/smail/config")) {
        while (<CF>) {
            if (/\A\s*hostnames?\s*=\s*(\S+)/) {
                $domain = (split(/:/,$1))[0];
                undef $domain if $^O eq 'darwin' && $domain =~ /\.local$/;
                last if defined $domain and $domain;
            }
        }
        close(CF) || die $!;

        return $domain if defined $domain;
    }

    if (eval {require Net::SMTP}) {
        my $host;

        for $host (qw(mailhost localhost)) {
            my $smtp = eval {Net::SMTP->new($host)};

            if (defined $smtp) {
                $domain = $smtp->domain;
                $smtp->quit;
                undef $domain if $^O eq 'darwin' && $domain =~ /\.local$/;
                last if defined $domain and $domain;
            }
        }
    }

    unless (defined $domain) {
        if ($self->_have_net_domain()) {
            ###################################################################
            # The below statement might possibly exhibit intermittent blocking
            # behavior. Be advised!
            ###################################################################
            $domain = Net::Domain::domainname();
            undef $domain if $^O eq 'darwin' && $domain =~ /\.local$/;
        }
    }

    $domain = "localhost" unless defined $domain;

    return $domain;
}

# From Mail::Util 1.74 (c) 1995-2001 Graham Barr (c) 2002-2005 Mark Overmeer
sub _mailaddress {
    my $self = shift;
    warn __PACKAGE__, ": _mailaddress\n" if $self->debug();

    my $mailaddress = $ENV{MAILADDRESS};
    $mailaddress ||= $ENV{USER}    ||
                     $ENV{LOGNAME} ||
                     eval {getpwuid($>)} ||
                     "postmaster";
    $mailaddress .= '@' . $self->_maildomain() unless $mailaddress =~ /\@/;
    $mailaddress =~ s/(^.*<|>.*$)//g;

    my $realname = $self->_realname();
    if ($realname) {
        $mailaddress = "$mailaddress ($realname)";
    }

    return $mailaddress;
}

sub _realname {
    my $self = shift;
    warn __PACKAGE__, ": _realname\n" if $self->debug();

    my $realname = '';

    $realname =
        eval {(split /,/, (getpwuid($>))[6])[0]} ||
        $ENV{QMAILNAME}                          ||
        $ENV{REALNAME}                           ||
        $ENV{USER};

    return $realname;
}

sub _is_a_perl_release {
    my $self = shift;
    warn __PACKAGE__, ": _is_a_perl_release\n" if $self->debug();

    my $perl = shift;

    return $perl =~ /^perl-?\d\.\d/;
}


# Next two subs courtesy of Casey West, Ricardo SIGNES, and Email::Date
# Visit the Perl Email Project at: http://emailproject.perl.org/
sub _tz_diff {
    my $self = shift;
    warn __PACKAGE__, ": _tz_diff\n" if $self->debug();

    my ($time) = @_;

    my $diff  =   Time::Local::timegm(localtime $time)
                - Time::Local::timegm(gmtime    $time);

    my $direc = $diff < 0 ? '-' : '+';
       $diff  = abs $diff;
    my $tz_hr = int( $diff / 3600 );
    my $tz_mi = int( $diff / 60 - $tz_hr * 60 );

    return ($direc, $tz_hr, $tz_mi);
}

sub _format_date {
    my $self = shift;
    warn __PACKAGE__, ": _format_date\n" if $self->debug();

    my ($time) = @_;
    $time = time unless defined $time;

    my ($sec, $min, $hour, $mday, $mon, $year, $wday) = (localtime $time);
    my $day   = (qw[Sun Mon Tue Wed Thu Fri Sat])[$wday];
    my $month = (qw[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec])[$mon];
    $year += 1900;

    my ($direc, $tz_hr, $tz_mi) = $self->_tz_diff($time);

    sprintf "%s, %d %s %d %02d:%02d:%02d %s%02d%02d",
      $day, $mday, $month, $year, $hour, $min, $sec, $direc, $tz_hr, $tz_mi;
}

=head1 NAME

Test::Reporter - sends test results to cpan-testers@perl.org

=head1 SYNOPSIS

  use Test::Reporter;

  my $reporter = Test::Reporter->new();

  $reporter->grade('pass');
  $reporter->distribution('Mail-Freshmeat-1.20');
  $reporter->send() || die $reporter->errstr();

  # or

  my $reporter = Test::Reporter->new();

  $reporter->grade('fail');
  $reporter->distribution('Mail-Freshmeat-1.20');
  $reporter->comments('output of a failed make test goes here...');
  $reporter->edit_comments(); # if you want to edit comments in an editor
  $reporter->send('afoxson@cpan.org') || die $reporter->errstr();

  # or

  my $reporter = Test::Reporter->new(
      grade => 'fail',
      distribution => 'Mail-Freshmeat-1.20',
      from => 'whoever@wherever.net (Whoever Wherever)',
      comments => 'output of a failed make test goes here...',
      via => 'CPANPLUS X.Y.Z',
  );
  $reporter->send() || die $reporter->errstr();

=head1 DESCRIPTION

Test::Reporter reports the test results of any given distribution to the CPAN
Testers. Test::Reporter has wide support for various perl5's and platforms. For
further information visit the below links:

=over 4

=item * L<http://cpantesters.perl.org/>

CPAN Testers reports (new site)

=item * L<http://testers.cpan.org/>

CPAN Testers reports (old site)

=item * L<http://cpantest.grango.org/>

The new CPAN Testers Wiki (thanks Barbie!)

=item * L<http://lists.cpan.org/showlist.cgi?name=cpan-testers>

The cpan-testers mailing list

=back

Test::Reporter itself--as a project--also has several links for your visiting
enjoyment:

=over 4

=item * L<http://code.google.com/p/test-reporter/>

Test::Reporter's master project page

=item * L<http://groups.google.com/group/test-reporter>

Discussion group for Test::Reporter

=item * L<http://code.google.com/p/test-reporter/w/list>

The Wiki for Test::Reporter

=item * L<http://repo.or.cz/w/test-reporter.git>

Test::Reporter's public git source code repository.

=item * L<http://search.cpan.org/dist/Test-Reporter/>

Test::Reporter on CPAN

=item * L<http://code.google.com/p/test-reporter/issues/list>

UNFORTUNATELY, WE ARE UNABLE TO ACCEPT TICKETS FILED WITH RT.

Please file all bug reports and enhancement requests at our Google Code issue
tracker. Thank you for your support and understanding.

=item * L<http://backpan.cpan.org/authors/id/F/FO/FOX/>

=item * L<http://backpan.cpan.org/authors/id/A/AF/AFOXSON/>

If you happen to--for some strange reason--be looking for primordial versions
of Test::Reporter, you can almost certainly find them at the above 2 links.

=back

=head1 METHODS

=over 4

=item * B<address>

Optional. Gets or sets the e-mail address that the reports will be
sent to. By default, this is set to cpan-testers@perl.org. You shouldn't
need this unless the CPAN Tester's change the e-mail address to send
report's to.

=item * B<comments>

Optional. Gets or sets the comments on the test report. This is most
commonly used for distributions that did not pass a 'make test'.

=item * B<debug>

Optional. Gets or sets the value that will turn debugging on or off.
Debug messages are sent to STDERR. 1 for on, 0 for off. Debugging
generates very verbose output and is useful mainly for finding bugs
in Test::Reporter itself.

=item * B<dir>

Optional. Defaults to the current working directory. This method specifies
the directory that write() writes test report files to.

=item * B<distribution>

Gets or sets the name of the distribution you're working on, for example
Foo-Bar-0.01. There are no restrictions on what can be put here.

=item * B<edit_comments>

Optional. Allows one to interactively edit the comments within a text
editor. comments() doesn't have to be first specified, but it will work
properly if it was.  Accepts an optional hash of arguments:

=over 4

=item * B<suffix>

Optional. Allows one to specify the suffix ("extension") of the temp
file used by B<edit_comments>.  Defaults to '.txt'.

=back

=item * B<errstr>

Returns an error message describing why something failed. You must check
errstr() on a send() in order to be guaranteed delivery. This is optional
if you don't intend to use Test::Reporter to send reports via e-mail,
see 'send' below for more information.

=item * B<from>

Optional. Gets or sets the e-mail address of the individual submitting
the test report, i.e. "afoxson@pobox.com (Adam Foxson)". This is
mostly of use to testers running under Windows, since Test::Reporter
will usually figure this out automatically. Alternatively, you can use
the MAILADDRESS environmental variable to accomplish the same.

=item * B<grade>

Gets or sets the success or failure of the distributions's 'make test'
result. This must be one of:

  grade     meaning
  -----     -------
  pass      all tests passed
  fail      one or more tests failed
  na        distribution will not work on this platform
  unknown   distribution did not include tests

=item * B<mail_send_args>

Optional. If you have MailTools installed and you want to have it
behave in a non-default manner, parameters that you give this
method will be passed directly to the constructor of
Mail::Mailer. See L<Mail::Mailer> and L<Mail::Send> for details. 

=item * B<message_id>

Returns an automatically generated Message ID. This Message ID will later
be included as an outgoing mail header in the test report e-mail. This was
included to conform to local mail policies at perl.org. This method courtesy
of Email::MessageID.

=item * B<mx>

Optional. Gets or sets the mail exchangers that will be used to send
the test reports. If you override the default values make sure you
pass in a reference to an array. By default, this contains the MX's
known at the time of release for perl.org. If you do not have
Mail::Send installed (thus using the Net::SMTP interface) and do have
Net::DNS installed it will dynamically retrieve the latest MX's. You
really shouldn't need to use this unless the hardcoded MX's have
become wrong and you don't have Net::DNS installed.

=item * B<new>

This constructor returns a Test::Reporter object. It will optionally accept
named parameters for: mx, address, grade, distribution, from, comments,
via, timeout, debug, dir, perl_version, and transport.

=item * B<perl_version>

Returns a hashref containing _archname, _osvers, and _myconfig based upon the
perl that you are using. Alternatively, you may supply a different perl (path
to the binary) as an argument, in which case the supplied perl will be used as
the basis of the above data.

=item * B<report>

Returns the actual content of a report, i.e.
"This distribution has been tested as part of the cpan-testers...". 
'comments' must first be specified before calling this method, if you have
comments to make and expect them to be included in the report.

=item * B<send>

Sends the test report to cpan-testers@perl.org and cc's the e-mail to the
specified recipients, if any. If you do specify recipients to be cc'd and
you do not have Mail::Send installed be sure that you use the author's
@cpan.org address otherwise they will not be delivered. You must check
errstr() on a send() in order to be guaranteed delivery. Technically, this
is optional, as you may use Test::Reporter to only obtain the 'subject' and
'report' without sending an e-mail at all, although that would be unusual.

=item * B<subject>

Returns the subject line of a report, i.e.
"PASS Mail-Freshmeat-1.20 Darwin 6.0". 'grade' and 'distribution' must
first be specified before calling this method.

=item * B<timeout>

Optional. Gets or sets the timeout value for the submission of test
reports. Default is 120 seconds. 

=item * B<transport>

Optional. Gets or sets the transport method. If you do not specify a transport,
one will be selected automatically on your behalf: If you're on Windows,
Net::SMTP will be selected, if you're not on Windows, Net::SMTP will be
selected unless Mail::Send is installed, in which case Mail::Send is used.

At the moment, this must be one of either 'Net::SMTP', or 'Mail::Send'.
Support for authenticated SMTP may soon be possibly added as well.

If you specify 'Mail::Send' as a transport, you can add an additional
argument in the form of an array reference which will be passed to the
constructor of the lower-level Mail::Mailer. This can be used to great
effect for all manner of fun and enjoyment. ;-)

This is not designed to be an extensible platform upon which to build
transport plugins. That functionality is planned for the next-generation
release of Test::Reporter, which will reside in the CPAN::Testers namespace.

=item * B<via>

Optional. Gets or sets the value that will be appended to
X-Reported-Via, generally this is useful for distributions that use
Test::Reporter to report test results. This would be something
like "CPANPLUS 0.036".

=item * B<write and read>

These methods are used in situations where you test on a machine that has
port 25 blocked and there is no local MTA. You use write() on the machine
that you are testing from, transfer the written test reports from the
testing machine to the sending machine, and use read() on the machine that
you actually want to submit the reports from. write() will write a file in
an internal format that contains 'From', 'Subject', and the content of the
report. The filename will be represented as:
grade.distribution.archname.osvers.seconds_since_epoch.pid.rpt. write()
uses the value of dir() if it was specified, else the cwd.

On the machine you are testing from:

  my $reporter = Test::Reporter->new
  (
    grade => 'pass',
    distribution => 'Test-Reporter-1.16',
  )->write();

On the machine you are submitting from:

  my $reporter;
  $reporter = Test::Reporter->new()->read('pass.Test-Reporter-1.16.i686-linux.2.2.16.1046685296.14961.rpt')->send() || die $reporter->errstr(); # wrap in an opendir if you've a lot to submit

write() also accepts an optional filehandle argument:

  my $fh; open $fh, '>-';  # create a STDOUT filehandle object
  $reporter->write($fh);   # prints the report to STDOUT

=back

=head1 CAVEATS

If you specify recipients to be cc'd while using send() (and you do not have
Mail::Send installed) be sure that you use the author's @cpan.org address
otherwise they may not be delivered, since the perl.org MX's are unlikely
to relay for anything other than perl.org and cpan.org.

=head1 COPYRIGHT

Copyright (c) 2007 Adam J. Foxson. All rights reserved.

=head1 LICENSE

This program is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

=over 4

=item * L<perl>

=item * L<Config>

=item * L<Net::SMTP>

=item * L<File::Spec>

=item * L<File::Temp>

=item * L<Net::Domain>

This is optional. If it's installed Test::Reporter will try even
harder at guessing your mail domain.

=item * L<Net::DNS>

This is optional. If it's installed Test::Reporter will dynamically
retrieve the mail exchangers for perl.org, instead of relying on the
MX's known at the time of this release.

=item * L<Mail::Send>

This is optional. If it's installed Test::Reporter will use Mail::Send
instead of Net::SMTP.

=back

=head1 AUTHOR

Adam J. Foxson E<lt>F<afoxson@pobox.com>E<gt> and
Richard Soderberg E<lt>F<rsod@cpan.org>E<gt>, with much deserved credit to
Kirrily "Skud" Robert E<lt>F<skud@cpan.org>E<gt>, and
Kurt Starsinic E<lt>F<Kurt.Starsinic@isinet.com>E<gt> for predecessor versions
(CPAN::Test::Reporter, and cpantest respectively).

=cut

1;
