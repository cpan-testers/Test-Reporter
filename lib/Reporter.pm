# $Revision: 1.13 $
# $Id: Reporter.pm,v 1.13 2002/08/12 07:18:48 afoxson Exp $

# Test::Reporter - reports test results to the CPAN testing service
# Copyright (c) 2002 Adam J. Foxson. All rights reserved.

# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package Test::Reporter;

use strict;
use Config;
use Carp;
use Net::SMTP;
use vars qw($VERSION $AUTOLOAD);

($VERSION) = '$Revision: 1.13 $' =~ /\s+(\d+\.\d+)\s+/;

local $^W;

sub new {
	my $type  = shift;
	my $class = ref($type) || $type;
	my $self  = {
		'_mx'           => ['perlmail.valueclick.com', 'lux.valueclick.com'],
		'_address'      => 'cpan-testers@perl.org',
		'_grade'        => undef,
		'_distribution' => undef,
		'_report'       => undef,
		'_subject'      => undef,
		'_from'         => undef,
		'_comments'     => '',
		'_errstr'       => '',
		'_timeout'      => 120,
	};

	bless $self, $class;

	$self->{_attr} = {   
		map {$_ => 1} qw(   
			_distribution _comments _errstr _timeout
		)
	};

	return $self;
}

sub subject {
	my $self = shift;

	croak __PACKAGE__, ": subject: grade and distribution must first be set\n"
		if not defined $self->{_grade} or not defined $self->{_distribution};

	my $subject = uc($self->{_grade}) . ' ' . $self->{_distribution} .
		" $Config{archname} $Config{osvers}";

	return $self->{_subject} = $subject;
}

sub report {
	my $self   = shift;
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
	my %grades = (
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

sub send {
	my ($self, @recipients) = @_;

	$self->from();
	$self->subject();
	$self->report();

	return unless $self->_verify();
	return $self->_send_smtp(@recipients);
}

sub _verify {
	my $self = shift;
	my @undefined;

	for my $key (keys %{$self}) {
		push @undefined, $key if not defined $self->{$key};
	}

	$self->errstr(__PACKAGE__ . ": Missing values for: " .
		join ', ', map {$_ =~ /^_(.+)$/} @undefined) if
		scalar @undefined > 0;
	$self->errstr() ? return 0 : return 1;
}

sub _send_smtp {
	my $self       = shift;
	my $helo       = $self->_maildomain();
	my $from       = $self->from();
	my @recipients = @_;
	my $success    = 0;
	my $smtp       = Net::SMTP->new((@{$self->{_mx}})[0], Hello => $helo,
						Timeout => $self->{_timeout});
	my $recipients;

	if (@recipients) {
		$recipients = join ', ', @recipients;
		chomp $recipients;
		chomp $recipients;
	}

	$success += $smtp->mail($from);
	$success += $smtp->to($self->{_address});
	$success += $smtp->cc(@recipients) if @recipients;
	$success += $smtp->data();
	$success += $smtp->datasend("From: $from\n");
	$success += $smtp->datasend("To: ", $self->{_address}, "\n");
	$success += $smtp->datasend("Cc: $recipients\n") if @recipients;
	$success += $smtp->datasend("Subject: ", $self->subject(), "\n");
	$success +=
		$smtp->datasend("X-reported-via: Test::Reporter $VERSION\n");
	$success += $smtp->datasend("\n");
	$success += $smtp->datasend($self->report());
	$success += $smtp->dataend();
	$success += $smtp->quit;

	if (@recipients) {
		$self->errstr(__PACKAGE__ .
			': Unable to send test report to one or more recipients') if
				$success != 13;
	}
	else {
		$self->errstr(__PACKAGE__ . ': Unable to send test report') if
			$success != 11;
	}

	$self->errstr() ? 0 : 1;
}

sub _realname {
	my $self     = shift;
	my $realname = '';

	$realname                                    =
		eval {(split /,/, (getpwuid($>))[6])[0]} ||
		$ENV{QMAILNAME}                          ||
		$ENV{REALNAME}                           ||
		$ENV{USER};

	return $realname;
}

# Adapted from Mail::Util
sub _maildomain {
	my $self       = shift;
	my @sendmailcf = qw(
		/etc
		/etc/sendmail
		/etc/ucblib
		/etc/mail
		/usr/lib
		/var/adm/sendmail
	);
	my $config = (grep(-r, map("$_/sendmail.cf", @sendmailcf)))[0];
	my $domain;

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
		$domain = $var{S} if defined $var{S};
		return $domain if defined $domain;
	}

	if (open(CF,"/usr/lib/smail/config")) {
		while (<CF>) {
			if (/\A\s*hostnames?\s*=\s*(\S+)/) {
				$domain = (split(/:/,$1))[0];
				last;
			}
		}
		close(CF);

		return $domain if defined $domain;
	}

	my $host;

	for $host (qw(mailhost localhost)) {
		my $smtp = eval {Net::SMTP->new($host)};

		if (defined $smtp) {
			$domain = $smtp->domain;
			$smtp->quit;
			last;
		}
	}

	unless (defined $domain) {
		if (eval {require Net::Domain}) {
			$domain = Net::Domain::domainname();
		}
	}

	$domain = "localhost" unless defined $domain;

	return $domain;
}

# Adapted from Mail::Util
sub _mailaddress {
	my $self     = shift;
	my $realname = $self->_realname();
	my $mailaddress;

	return $self->{_from} if defined $self->{_from};

	$mailaddress            =
		$ENV{MAILADDRESS}   ||
		$ENV{USER}          ||
		$ENV{LOGNAME}       ||
		eval {getpwuid($>)} ||
		"postmaster";

	$mailaddress .= '@' . $self->_maildomain() unless $mailaddress =~ /\@/;
	$mailaddress =~ s/(^.*<|>.*$)//g;

	if ($realname) {
		$mailaddress = "$mailaddress ($realname)";
	}
	else {
		$mailaddress = $mailaddress;
	}

	return $mailaddress;
}

sub from {
	my $self = shift;

	if (@_) {
		$self->{_from} = shift;
	}
	else {
		$self->{_from} = $self->_mailaddress();
	}

	return $self->{_from};
}

sub AUTOLOAD {
	my $self               = $_[0];
	my ($package, $method) = ($AUTOLOAD =~ /(.*)::(.*)/);

	return if $method =~ /^DESTROY$/;

	unless ($self->{_attr}->{"_$method"}) {
		croak __PACKAGE__ . ": No such method: $method; aborting";
	}

	my $code = q{
		sub {   
			my $self = shift;
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

1;

__DATA__
=pod

=head1 NAME

Test::Reporter - reports test results to the CPAN testing service

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
  $reporter->send('afoxson@pobox.com') || die $reporter->errstr();

  NOTE: THIS VERSION OF Test::Reporter SHOULD BE CONSIDERED BETA.
  THE INTERFACE MAY CHANGE.

=head1 DESCRIPTION

Test::Reporter reports the test results of any given distribution to the
CPAN testing service. See B<http://testers.cpan.org/> for details.

=head1 METHODS

=over 4

=item * B<new>

This constructor returns a Test::Reporter object. It currently accepts no
parameters, but will likely take named parameters in a future version.

=item * B<subject>

Returns the subject line of a report, i.e.
"PASS Mail-Freshmeat-1.20 Darwin 6.0". 'grade' and 'distribution' must
first be specified before calling this method.

=item * B<report>

Returns the actual content of a report, i.e.
"This distribution has been tested as part of the cpan-testers...". 
'comments' must first be specified before calling this method, if you have
comments to make and expect them to be included in the report.

=item * B<comments>

Gets or sets the comments on the test report. This is optional, and most
commonly used for distributions that did not pass a 'make test'.

=item * B<errstr>

Returns an error message describing why something failed. You must check
errstr() on a send() in order to be guaranteed delivery.

=item * B<from>

Gets or sets the e-mail address of the individual submitting the test
report, i.e. "Adam J. Foxson <afoxson@pobox.com>". This is mostly
of use to testers running under Windows, since Test::Reporter will
usually figure this out automatically.

=item * B<grade>

Gets or sets the success or failure of the distributions's 'make test'
result. This must be one of:

  grade     meaning
  -----     -------
  pass      all tests passed
  fail      one or more tests failed
  na        distribution will not work on this platform
  unknown   distribution did not include tests

=item * B<distribution>

Gets or sets the name of the distribution you're working on, for example
Foo-Bar-0.01. There are no restrictions on what can be put here.

=item * B<send>

Sends the test report to cpan-testers@perl.org and cc's the e-mail to the
specified recipients, if any. If you do specify recipients to be cc'd
be sure that you use the author's @cpan.org address otherwise they will
not be delivered.

=item * B<timeout>

Gets or sets the timeout value for the submission of test reports. 

=back

=head1 TODO

  - More detailed error messages and reporting.
  - More tests.
  - Possibly use Net::DNS to get MX's for perl.org.
  - Cycle through all available MX servers, instead of just the first.
  - Encoding of data may be necessary.
  - Allow the constructor to take named parameters.

=head1 COPYRIGHT

Copyright (c) 2002 Adam J. Foxson. All rights reserved.

=head1 LICENSE

This program is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>

=head1 AUTHOR

Adam J. Foxson <afoxson@pobox.com>, with much deserved credit to
Kirrily "Skud" Robert <skud@cpan.org>, and
Kurt Starsinic E<lt>F<Kurt.Starsinic@isinet.com>E<gt> for predecessor
versions (CPAN::Test::Reporter, and cpantest respectively).

=cut
