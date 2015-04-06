use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }
package Test::Reporter::Transport::Null;

our $VERSION = '1.63';

use base 'Test::Reporter::Transport';

sub new {
  return bless {}, shift;
}

sub send {
  return 1; # do nothing
}

1;

# ABSTRACT: Null transport for Test::Reporter

__END__

=for Pod::Coverage new send

=head1 SYNOPSIS

    my $report = Test::Reporter->new(
        transport => 'Null',
    );

=head1 DESCRIPTION

This module provides a "null" transport option that does nothing when
C<send()> is called.

=head1 USAGE

See L<Test::Reporter> and L<Test::Reporter::Transport> for general usage
information.

=cut

