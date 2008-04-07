use strict;
use warnings;
package Test::Reporter::Transport::Net::SMTP::TLS;
use base 'Test::Reporter::Transport::Net::SMTP';
use vars qw/$VERSION/;
$VERSION = '1.39_03';
$VERSION = eval $VERSION;

use Net::SMTP::TLS;

1;
