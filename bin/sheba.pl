#!/usr/bin/perl

use strict;
use warnings;

use 5.10.0;

use Munin::Node::OS;
use Git;
use List::PowerSet qw( powerset );
use Tie::Pick;
use Data::Dumper;


# returns a config hash thing
sub load_config
{
    return {
        branches => [qw(
            origin/master
        )],

        parrot_upstream => 'git://github.com/parrot/parrot.git',
        parrot_clone    => '/home/local/mlb/.smokers/parrot1',

        parrot_configs => [
            [],
            [qw( --cc=g++ --link=g++ --ld=g++ )],
            [qw( --cc=clang --link=clang --ld=clang )],
            [qw( --without-gmp )],
            [qw( --without-icu )],
            [qw( --without-libffi )],
            [qw( --without-zlib )],
            [qw( --optimize )],
            [qw( --optimize --without-gmp )],
            [qw( --optimize --without-icu )],
            [qw( --optimize --without-libffi )],
            [qw( --optimize --without-zlib )],
            [qw( --without-gettext --without-gmp --without-libffi --without-extra-nci-thunks --without-opengl --without-readline --without-pcre --without-zlib --without-threads --without-icu )],
            [qw( --without-gettext --without-gmp --without-libffi --without-extra-nci-thunks --without-opengl --without-readline --without-pcre --without-zlib --without-threads --without-icu --optimize )],
            [qw( --optimize --without-threads )],
            [qw( --without-threads )],
            ('random') x 10,
        ],

        parrot_all_config_opts => [
            [qw( --cc=clang --link=clang --ld=clang )],
            [qw( --cc=g++ --link=g++ --ld=g++ )],
            qw(
            --optimize
            --without-threads
            --without-core-nci-thunks
            --without-extra-nci-thunks
            --without-gettext
            --without-gmp
            --without-libffi
            --without-opengl
            --without-readline
            --without-pcre
            --without-zlib
            --without-icu
        )],

        make_jobs => 6,
        test_jobs => 6,

        harness_verbosity => -2,
    };
}


# list of configs to test.  each element is an arrayref that will be passed to
# Configure.pl, or the string 'random', which will be replaced with a randomly
# generated group of options.
#
# FIXME it's actually random now, but only at the cost of evil gut-poking
sub parrot_configs
{
    my ($config) = @_;

    my $ps = random_config_generator(@{$config->{parrot_all_config_opts}});
    return map { $_ eq 'random' ? Tie::Pick::FETCH($ps) : $_ } @{$config->{parrot_configs}};
}


# returns a tied scalar that pops out a random arrayref of configuration
# options picked from the arguments.
sub random_config_generator
{
    tie my $ps => 'Tie::Pick' => powerset(@_);
    return $ps;
}


# return a handle to a copy of the repository for running tests in
# FIXME this is a terrible name.  it should hint that a chdir() will happen.
sub repository
{
    my ($dir) = @_;

    chdir $dir or die "Unable to change to '$dir': $!";

    return Git->repository(DIRECTORY => $dir);
}


# flattens a list
sub _flatten { return map { ref eq 'ARRAY' ? @$_ : $_ } @_ }


# flattens @cmd, and runs it in a subprocess.  if it fails, spew the output to
# the screen in the hopes that it might be useful.
#
# FIXME lots.  report errors in a better way.  enable some sort of debugging
# Output.  blah blah blah.
sub _run_command
{
    my (@cmd) = @_;

    @cmd = _flatten(@cmd);

    my $res = Munin::Node::OS->run_as_child(
        3600,  # in seconds.  FIXME get rid of this.
        sub { exec {$cmd[0]} @cmd or die "Error exec()ing @cmd: $!" },
    );

    if ($res->{retval}) {
        my $cmd_str = join ' ', @cmd;
        my $cmd_exit   = $res->{retval} >> 8;
        my $cmd_signal = $res->{retval} & 127;

        # FIXME report stdout/err for debugging...
        warn Dumper $res;

        warn "'$cmd_str' exited with status $cmd_exit/$cmd_signal.\n";
        return 0;
    }

    return 1;
}


# get all nicely scrubbed up
sub make_clean { return _run_command(qw( make --silent realclean )) }


# configure parrot
sub configure { return _run_command(qw( perl Configure.pl --silent ), @_) }


# make Parrot
sub make { return _run_command(qw( make -j6 --silent )) }


# run the tests
sub make_test { return _run_command(qw( make --silent test )) }


sub main
{
    my (@ARGV) = @_;

    # load the config
    my $config = load_config();

    local $ENV{TEST_JOBS}       = $config->{test_jobs};
    local $ENV{HARNESS_VERBOSE} = $config->{harness_verbosity};

    # get the test repository, and move there
    my $repo = repository($config->{parrot_clone});

    # make sure it's up-to-date
    $repo->command('fetch');

    # fetch the branches and configurations to test
    my @branches       = @{$config->{branches}};
    my @configurations = parrot_configs($config);

    foreach my $branch (@branches) {
        # checkout the branch
        $repo->command(qw( checkout -q ), $branch);

        foreach my $config (@configurations) {
            make_clean() if -e 'Makefile';

            configure(@$config)
                && make()
                && make_test()
                && next;

            say "Error running config: ", join ' ', _flatten(@$config);
        }
    }

    return 0;
}


exit main(@ARGV) unless caller;


# vim: sw=4 : ts=4 : et
