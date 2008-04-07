use strict;
use warnings;
package Test::Reporter::Transport::HTTPGateway;
use base 'Test::Reporter::Transport';
use vars qw/$VERSION/;
$VERSION = '1.39_03';
$VERSION = eval $VERSION;

use LWP::UserAgent;

sub new {
  my ($class, $url, $key) = @_;

  die "invalid gateway URL: must be absolute http or https URL"
    unless $url =~ /\Ahttps?:/i;

  bless { gateway => $url, key => $key } => $class;
}

sub send {
  my ($self, $report) = @_;

  # construct the "via"
  my $report_class   = ref $report;
  my $report_version = $report->VERSION;
  my $via = "$report_class $report_version";
  $via .= ', via ' . $report->via if $report->via;

  # post the report
  my $ua = LWP::UserAgent->new;
  $ua->timeout(60);
  $ua->env_proxy;

  my $form = {
    key     => $self->{key},
    via     => $via,
    from    => $report->from,
    subject => $report->subject,
    report  => $report->report,
  };

  my $res = $ua->post($self->{gateway}, $form);

  return 1 if $res->is_success;

  die sprintf "HTTP error: %s: %s", $res->status_line, $res->content;
}

1;
