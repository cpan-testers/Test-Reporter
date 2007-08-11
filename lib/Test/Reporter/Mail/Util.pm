# Test::Reporter::Mail::Util.pm
#
# Copyright (c) 1995-2001 Graham Barr <gbarr@pobox.com>. All rights reserved.
# Copyright (c) 2002-2003 Mark Overmeer <mailtools@overmeer.net>
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

package Test::Reporter::Mail::Util;

use strict;
use vars qw($VERSION @ISA @EXPORT $mailaddress $maildomain $realname);
use Exporter;

$VERSION = '1.58';
@ISA = qw(Exporter);
@EXPORT = qw(_realname _maildomain _mailaddress $mailaddress $maildomain $realname);

local $^W;

sub _realname {
	my $self = shift;

	warn __PACKAGE__, ": _realname\n" if $self->debug();

	return $realname if defined $realname;

	$realname = '';
	$realname                                    =
		eval {(split /,/, (getpwuid($>))[6])[0]} ||
		$ENV{QMAILNAME}                          ||
		$ENV{REALNAME}                           ||
		$ENV{USER};

	return $realname;
}

sub _maildomain {
	my $self = shift;

	warn __PACKAGE__, ": _maildomain\n" if $self->debug();

	return $maildomain if defined $maildomain;

	$maildomain = $ENV{MAILDOMAIN};

	return $maildomain if defined $maildomain;

	local *CF;
	local $_;
	my @sendmailcf = qw(
		/etc
		/etc/sendmail
		/etc/ucblib
		/etc/mail
		/usr/lib
		/var/adm/sendmail
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
		$maildomain = $var{j} if defined $var{j};
		$maildomain = $var{M} if defined $var{M};

		$maildomain = $1
			if($maildomain && $maildomain =~ m/([A-Za-z0-9](?:[\.\-A-Za-z0-9]+))/ );

		return $maildomain if defined $maildomain;
	}

	if (open(CF,"/usr/lib/smail/config")) {
		while (<CF>) {
			if (/\A\s*hostnames?\s*=\s*(\S+)/) {
				$maildomain = (split(/:/,$1))[0];
				last;
			}
		}
		close(CF) || die $!;

		return $maildomain if defined $maildomain;
	}

	my $host;

	for $host (qw(mailhost localhost)) {
		my $smtp = Net::SMTP->new($host);

		if (defined $smtp) {
			$maildomain = $smtp->domain;
			$smtp->quit;
			last;
		}
	}

	unless (defined $maildomain) {
		if ($self->_have_net_domain()) {
			$maildomain = Net::Domain::domainname();
		}
	}

	$maildomain = "localhost" unless defined $maildomain;

	return $maildomain;
}

sub _mailaddress {
	my $self = shift;

	warn __PACKAGE__, ": _mailaddress\n" if $self->debug();

	return $self->{_from} if defined $self->{_from};
	return $mailaddress if defined $mailaddress;

	my $realname = $self->_realname();

	$mailaddress = $ENV{MAILADDRESS};

	unless ($mailaddress || $^O ne 'MacOS') {
		my %InternetConfig;
		require Mac::InternetConfig;
		Mac::InternetConfig->import();
		$mailaddress = $InternetConfig{kICEmail()};
	}

	$mailaddress ||=
		$ENV{USER}          ||
		$ENV{LOGNAME}       ||
		eval {getpwuid($>)} ||
		"postmaster";

	$mailaddress .= '@' . $self->_maildomain() unless $mailaddress =~ /\@/;
	$mailaddress =~ s/(^.*<|>.*$)//g;

	if ($realname) {
		$mailaddress = "$mailaddress ($realname)";
	}

	return $mailaddress;
}

1;

__DATA__
=pod

=head1 NAME

Test::Reporter::Mail::Util - mail utility functions

=head1 SYNOPSIS

use Test::Reporter::Mail::Util qw( ... );

=head1 DESCRIPTION

This package provides several mail related utility functions. Any function
required must by explicitly listed on the use line to be exported into
the calling package.

=head2 maildomain()

Attempt to determine the current uers mail domain string via the following
methods

=over 4

=item *  Look for the MAILDOMAIN enviroment variable, which can be set from outside the program.

=item *  Look for a sendmail.cf file and extract DH parameter

=item *  Look for a smail config file and usr the first host defined in hostname(s)

=item *  Try an SMTP connect (if Net::SMTP exists) first to mailhost then localhost

=item *  Use value from Net::Domain::domainname (if Net::Domain exists)

=back

=head2 mailaddress()

Return a guess at the current users mail address. The user can force
the return value by setting the MAILADDRESS environment variable.

=head2 realname()

Attempts to get the reporter's real name, i.e. whatever happens to be in
the GCOS field.

=head1 AUTHOR

Graham Barr.

Maintained by Mark Overmeer <mailtools@overmeer.net>

=head1 COPYRIGHT

Copyright (c) 2002-2003 Mark Overmeer, 1995-2001 Graham Barr. All rights
reserved. This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
