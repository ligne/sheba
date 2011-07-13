#!/usr/bin/perl
#
# Builds and tests the Parrot in the current directory.
#

use strict;
use warnings;

use 5.10.0;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Sheba::Tester;

my $tester = Sheba::Tester->new();

exit $tester->run_tests;


# vim: sw=4 : ts=4 : et
