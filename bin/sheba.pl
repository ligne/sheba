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


sub main
{
#    local $ENV{TEST_JOBS}       = $config->{test_jobs};
#    local $ENV{HARNESS_VERBOSE} = $config->{harness_verbosity};

    my $tester = Sheba::Tester->new();

    return $tester->run_tests;
}


exit main(@ARGV) unless caller;


# vim: sw=4 : ts=4 : et
