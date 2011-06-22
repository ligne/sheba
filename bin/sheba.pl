#!/usr/bin/perl
#
# Builds and tests the Parrot in the current directory.
#

use strict;
use warnings;

use 5.10.0;

use IPC::Run       qw( run );
use List::PowerSet qw( powerset );
use Tie::Pick;


# returns a config hash thing
sub load_config
{
    return {
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

    my $args = pop @cmd if ref $cmd[-1] eq 'HASH';

    unless (run \@cmd, '>&', \(my $out_and_err)) {
        my $exit = $?;
        my $cmd_str = join ' ', @cmd;
        my $cmd_exit   = $exit >> 8;
        my $cmd_signal = $exit & 127;

        say '#' x 80;
        say "'$cmd_str' exited with status $cmd_exit/$cmd_signal.\n";
        say $out_and_err;
        say '#' x 80;

        return 0;
    }

    return 1;
}


# get all nicely scrubbed up
sub make_clean { return _run_command(qw( make --silent realclean )) }

# configure parrot
sub configure { return _run_command(qw( perl Configure.pl --silent ), @_) }

# make Parrot
sub make { return _run_command(qw( make -j6 --silent ), @_) }

# run the tests
sub make_test { return _run_command(qw( make --silent test )) }


sub main
{
    # load the config
    my $config = load_config();

    local $ENV{TEST_JOBS}       = $config->{test_jobs};
    local $ENV{HARNESS_VERBOSE} = $config->{harness_verbosity};

    # fetch the configurations to test
    my @configurations = parrot_configs($config);

    foreach my $config (@configurations) {
        my @config = _flatten(@$config);
        # FIXME still build, just suppress errors.  then report if it built ok.
        if ('--cc=clang' ~~ @config and '--optimize' ~~ @config) {
            next;
        }

        make_clean() if -e 'Makefile';

        configure(@config)
            && make()
            && make_test()
            && next;

        say "Error running config: ", join ' ', @config;
    }

    return 0;
}


exit main(@ARGV) unless caller;


# vim: sw=4 : ts=4 : et
