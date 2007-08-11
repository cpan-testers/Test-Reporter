# $Revision: 1.19 $
# $Id: Reporter.pm,v 1.19 2003/03/05 07:26:35 afoxson Exp $

# Test::Reporter - sends test results to cpan-testers@perl.org
# Copyright (c) 2003 Adam J. Foxson. All rights reserved.

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
use File::Temp;
use Test::Reporter::Mail::Util;
use Test::Reporter::Date::Format;
use vars qw($VERSION $AUTOLOAD $fh $Report $MacMPW $MacApp $dns $domain $send);

$MacMPW    = $^O eq 'MacOS' && $MacPerl::Version =~ /MPW/;
$MacApp    = $^O eq 'MacOS' && $MacPerl::Version =~ /Application/;
($VERSION) = '$Revision: 1.19 $' =~ /\s+(\d+\.\d+)\s+/;

local $^W;

sub FAKE_NO_NET_DNS() {0}    # for debugging only
sub FAKE_NO_NET_DOMAIN() {0} # for debugging only
sub FAKE_NO_MAIL_SEND() {0}  # for debugging only

sub new {
	my $type  = shift;
	my $class = ref($type) || $type;
	my $self  = {
		'_mx'             => ['mx1.x.perl.org', 'mx2.x.perl.org'],
		'_address'        => 'cpan-testers@perl.org',
		'_grade'          => undef,
		'_distribution'   => undef,
		'_report'         => undef,
		'_subject'        => undef,
		'_from'           => undef,
		'_comments'       => '',
		'_errstr'         => '',
		'_via'            => '',
		'_mail_send_args' => '',
		'_timeout'        => 120,
		'_debug'          => 0,
		'_dir'            => '',
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
		mx address grade distribution from comments via timeout debug dir);
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

	my $subject = uc($self->{_grade}) . ' ' . $self->{_distribution} .
		" $Config{archname} $Config{osvers}";

	return $self->{_subject} = $subject;
}

sub report {
	my $self = shift;
	warn __PACKAGE__, ": report\n" if $self->debug();

	my $report = qq(
		This distribution has been tested as part of the cpan-testers
		effort to test as many new uploads to CPAN as possible.  See
		http://testers.cpan.org/

		Please cc any replies to cpan-testers\@perl.org to keep other
		test volunteers informed and to prevent any duplicate effort.
	);

	$report =~ s/\n//;
	$report =~ s/\t{2}//g;

	if (not $self->{_comments}) {
		$report .= "\n\n--\n\n";
	}
	else {
		$report .= "\n--\n" . $self->{_comments} . "\n--\n\n";
	}

	$report .= Config::myconfig();

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

sub edit_comments {
	my $self = shift;
	warn __PACKAGE__, ": edit_comments\n" if $self->debug();

	($fh, $Report) = File::Temp::tempfile(UNLINK => 1);

	print $fh $self->{_comments};

	$self->_start_editor();

	my $comments;
	{
		local $/;
		open FH, $Report or die __PACKAGE__, ": Can't open comment file: $!";
		$comments = <FH>;
		close FH or die __PACKAGE__, ": Can't close comment file: $!";
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

	if ($self->_have_mail_send()) {
		return $self->_mail_send(@recipients);
	}
	else {
		return $self->_send_smtp(@recipients);
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

	my $file = "$dir/$grade.$distribution.$Config{archname}.$Config{osvers}.${\(time)}.$$.rpt";

	open REPORT, ">$file" or die __PACKAGE__, ": Can't open report file: $!";
	print REPORT "From: $from\n";
	print REPORT "Subject: $subject\n";
	print REPORT "Report: $report";
	close REPORT or die __PACKAGE__, ": Can't close report file: $!";

	return $file;
}

sub read {
	my ($self, $file) = @_;
	warn __PACKAGE__, ": read\n" if $self->debug();

	my $buffer;

	{
		local $/;
		open REPORT, $file or die __PACKAGE__, ": Can't open report file: $!";
		$buffer = <REPORT>;
		close REPORT or die __PACKAGE__, ": Can't close report file: $!";
	}

	if (my ($from, $subject, $report) = $buffer =~ /^From:\s(.+)Subject:\s(.+)Report:\s(.+)$/s) {
		my ($grade, $distribution) = (split /\s/, $subject)[0,1];
		$self->from($from) unless $self->from();
		$self->{_subject} = $subject;
		$self->{_report} = $report;
		$self->{_grade} = lc $grade;
		$self->{_distribution} = $distribution;
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

	for my $recipient (sort @recipients) {
		if ($recipient =~ /(?:perl|cpan)\.org$/) {
			push @tmprecipients, $recipient;
		}
		else {
			push @bad, $recipient;
		}
	}

	if (scalar @bad  > 0) {
		warn __PACKAGE__, ": Will not attempt to cc the following recipients since perl.org MX's will not relay for them. Either install Mail::Send, or only cc address ending in cpan.org or perl.org: ${\(join ', ', @bad)}.\n";
	}

	@recipients = @tmprecipients;

	for my $mx (@{$self->{_mx}}) {
		$smtp = Net::SMTP->new((@{$self->{_mx}})[0], Hello => $helo,
			Timeout => $self->{_timeout}, Debug => $debug);

		last if defined $smtp;
		$fail++;
	}

	if ($fail == scalar @{$self->{_mx}}) {
		$self->errstr(__PACKAGE__ . ': Unable to connect to any MX\'s');
		return 0;
	}

	$via = ', via ' . $via if $via;

	if (@recipients) {
		$recipients = join ', ', @recipients;
		chomp $recipients;
		chomp $recipients;
	}

	$success += $smtp->mail($from);
	$success += $smtp->to($self->{_address});
	$success += $smtp->cc(@recipients) if @recipients;
	$success += $smtp->data();
	$success += $smtp->datasend("Date: ", time2str("%a, %e %b %Y %T %z", time), "\n");
	$success += $smtp->datasend("Subject: ", $self->subject(), "\n");
	$success += $smtp->datasend("From: $from\n");
	$success += $smtp->datasend("To: ", $self->{_address}, "\n");
	$success += $smtp->datasend("Cc: $recipients\n") if @recipients && $success == 8;
	$success +=
		$smtp->datasend("X-Reported-Via: Test::Reporter ${VERSION}$via\n");
	$success += $smtp->datasend("\n");
	$success += $smtp->datasend($self->report());
	$success += $smtp->dataend();
	$success += $smtp->quit;

	if (@recipients) {
		$self->errstr(__PACKAGE__ .
			": Unable to send test report to one or more recipients\n") if $success != 14;
	}
	else {
		$self->errstr(__PACKAGE__ . ": Unable to send test report\n") if $success != 12;
	}

	return $self->errstr() ? 0 : 1;
}

sub from {
	my $self = shift;
	warn __PACKAGE__, ": from\n" if $self->debug();

	if (@_) {
		$self->{_from} = shift;
	}
	else {
		$self->{_from} = $self->_mailaddress();
	}

	return $self->{_from};
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

	return $dns if defined $dns;
	return 0 if FAKE_NO_NET_DNS;

	$dns = eval {require Net::DNS};
}

sub _have_net_domain {
	my $self = shift;
	warn __PACKAGE__, ": _have_net_domain\n" if $self->debug();

	return $domain if defined $domain;
	return 0 if FAKE_NO_NET_DOMAIN;

	$domain = eval {require Net::Domain};
}

sub _have_mail_send {
	my $self = shift;
	warn __PACKAGE__, ": _have_mail_send\n" if $self->debug();

	return $send if defined $send;
	return 0 if FAKE_NO_MAIL_SEND;

	$send = eval {require Mail::Send};
}

sub _start_editor_mac {
	my $self = shift;
	warn __PACKAGE__, ": _start_editor_mac\n" if $self->debug();

	my $editor = shift;

	use vars '%Application';
	for my $mod (qw(Mac::MoreFiles Mac::AppleEvents::Simple Mac::AppleEvents)) {
		eval qq(require $mod) or die __PACKAGE__, ": Can't load $mod.\n";
		eval qq($mod->import());
	}

	my $app = $Application{$editor};
	die __PACKAGE__, ": Application with ID '$editor' not found.\n" if !$app;

	my $obj = 'obj {want:type(cobj), from:null(), ' .
		'form:enum(name), seld:TEXT(@)}';
	my $evt = do_event(qw/aevt odoc MACS/,
		"'----': $obj, usin: $obj", $Report, $app);

	if (my $err = AEGetParamDesc($evt->{REP}, 'errn')) {
		die __PACKAGE__, ": AppleEvent error: ${\AEPrint($err)}.\n";
	}

	$self->_prompt('Done?', 'Yes') if $MacMPW;
	MacPerl::Answer('Done?') if $MacApp;
}

sub _start_editor {
	my $self = shift;
	warn __PACKAGE__, ": _start_editor\n" if $self->debug();

	my $editor = $ENV{VISUAL} || $ENV{EDITOR} || $ENV{EDIT}
		|| ($^O eq 'VMS'     and "edit/tpu")
		|| ($^O eq 'MSWin32' and "notepad")
		|| ($^O eq 'MacOS'   and 'ttxt')
		|| 'vi';

	$editor = $self->_prompt('Editor', $editor) unless $MacApp;

	if ($^O eq 'MacOS') {
		$self->_start_editor_mac($editor);
	}
	else {
		die __PACKAGE__, ": The editor `$editor' could not be run" if system "$editor $Report";
		die __PACKAGE__, ": Report has disappeared; terminated" unless -e $Report;
		die __PACKAGE__, ": Empty report; terminated" unless -s $Report > 2;
	}
}

sub _prompt {
	my $self = shift;
	warn __PACKAGE__, ": _prompt\n" if $self->debug();

	my ($label, $default) = @_;

	printf "$label%s", ($MacMPW ? ":\n$default" : " [$default]: ");
	my $input = scalar <STDIN>;
	chomp $input;

	return (length $input) ? $input : $default;
}

1;
