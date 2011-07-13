#!/usr/bin/perl
#
# Runs tests against one or more git branches.
#

use strict;
use warnings;

use 5.10.0;

use Git;
use File::Spec ();

use FindBin;
use lib "$FindBin::Bin/../lib";

use Sheba::Tester;


# returns a config hash thing
sub load_config
{
    return {
        branches => [
            'origin/master',
        ],
        parrot_upstream => 'git://github.com/parrot/parrot.git',
        parrot_clone    => '/home/local/mlb/.smokers/parrot1',

        #use_tmp => 1,
        tmpdir => '/dev/shm',
    };
}


# return a handle to a copy of the repository for running tests in.
#
# FIXME this is a terrible name.  it should hint that a chdir() will happen.
sub repository
{
    my ($dir) = @_;

    chdir $dir or die "Unable to change to '$dir': $!";

    return Git->repository(DIRECTORY => $dir);
}


# return a list of branches to test.
#
# FIXME work out what branches have changed, either since last check, or $n
# hours
sub get_branches { return @{(shift)->{branches}} }


sub main
{
    my ($branch) = @_;

    # load the config
    my $config = load_config();

    # get the test repository, and move there
    my $repo = repository($config->{parrot_clone});

    # get the branches to test
    my @branches = get_branches($config);

    # make sure the repository is up-to-date
    $repo->command('fetch');

    foreach my $b (@branches) {
        $repo->command(qw( checkout -q ), $b);
        my $tester = Sheba::Tester->new();
        $tester->run_tests();
    }

    return 0;
}


exit main(@ARGV) unless caller;


# vim: sw=4 : ts=4 : et
