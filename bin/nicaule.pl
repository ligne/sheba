#!/usr/bin/perl
#
# Runs tests against one or more git branches.
#

use strict;
use warnings;

use 5.10.0;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Git;

use Sheba::Tester;
use Sheba::Repository;


my @branches = (
    'origin/master',
);


sub main
{
    my ($branch) = @_;

    my $tester = Sheba::Tester->new();

    # get the test repository, and move there
    my $repo = Sheba::Repository->new();
    $repo->prepare_repo;

    foreach my $b (@branches) {
        $repo->command(qw( checkout -q --force ), $b);
        $tester->run_tests();
    }

    # need to chdir out of the tempdir, or it can't be cleaned up
    chdir '/';

    return 0;
}


exit main(@ARGV) unless caller;


# vim: sw=4 : ts=4 : et
