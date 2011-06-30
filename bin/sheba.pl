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
use BSD::Resource;


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

        priority => 10,   # niceness
        limits => {
            # see BSD::Resource docs for details
            cpu      => 600,  # cpu time in seconds
            as       => 1e9,  # memory usage (stack, heap, et al.)
        },
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


sub set_limits
{
    my ($priority, $limits) = @_;

    if (defined $priority) {
        # catch exceptions when setpriority(2) isn't available.
        # which = PRIO_PROCESS, who = self.
        eval { setpriority(0, 0, $priority) }
            or warn "Failed to set priority: $!\n";
    }

    return unless $limits;

    my $rlimits = get_rlimits();

    while (my ($name, $limit) = each %$limits) {
        my $resource = $rlimits->{"RLIMIT_\U$name\E"};
        say "Limiting '$name' is not supported on this system"
                unless defined $resource;

        # set both hard and soft to the same limit
        setrlimit($resource, $limit, $limit)
                or say "Failed to set priority: $!";
    }
}


# _run_command(@command, [ \%options ]);
#
# runs @command in a subprocess.  returns true if it completed ok, false
# otherwise.
#
# by default it prints the std{out,err} output iff the command failed, in the
# hopes that it might be useful.
#
# %options modify behaviour.  currently it only supports 'todo', which is
# analogous to todo blocks in Test::More:  the command is expected to fail, so
# output is suppressed by default
sub _run_command
{
    my (@cmd) = @_;

    my $opts = pop @cmd if ref $cmd[-1] eq 'HASH';

    @cmd = grep defined, @cmd;  # FIXME shoudn't really be necessary

    my $success = run \@cmd, '>&', \(my $out_and_err);
    my $exit    = $?;

    my $cmd_str = join ' ', @cmd;

    if ($success and $opts->{todo}) {
        say '#' x 80;
        say "'$cmd_str' unexpectedly succeeded.\n";
        say '#' x 80;
    }

    if (not $success and not $opts->{todo}) {
        my $cmd_exit   = $exit >> 8;
        my $cmd_signal = $exit & 127;

        say '#' x 80;
        say "'$cmd_str' exited with status $cmd_exit/$cmd_signal.\n";
        say $out_and_err;

        return 0;
    }

    return $success;
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

    set_limits($config->{priority}, $config->{limits});

    # fetch the configurations to test
    my @configurations = parrot_configs($config);

    foreach my $config (@configurations) {
        my @config = _flatten(@$config);
        my $make_opts;

        if ('--cc=clang' ~~ @config and '--optimize' ~~ @config) {
            $make_opts->{todo} = 1;
        }

        make_clean() if -e 'Makefile';

        configure(@config)
            && make($make_opts)
            && make_test()
            && next;

        say "Error running config: ", join ' ', @config;
    }

    return 0;
}


exit main(@ARGV) unless caller;


# vim: sw=4 : ts=4 : et
