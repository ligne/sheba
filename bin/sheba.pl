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


# runs @command in a subprocess.  returns true if it completed ok, and a
# hashref with some diagnostic information otherwise.
sub _run_command
{
    my (@cmd) = @_;

    my $success = run \@cmd, '&>', \(my $out_and_err);
    my $exit = $? or return;

    return {
        command => "@cmd",
        exit    => $exit >> 8,
        signal  => $exit & 127,
        output  => \$out_and_err,
    };
}


# takes an arrayref with a set of configure options, and tests it.  reports any
# problems to stdout.
sub test_configuration
{
    my ($config, $configuration) = @_;

    my @configuration = _flatten(@$configuration);

    # FIXME this is quite ugly...
    my @build_commands = (
        [qw( perl Configure.pl --silent ), @configuration ],
        [qw( make --silent ), "-j$config->{make_jobs}" ],
        [qw( make --silent test )],
    );

    _run_command(qw( make --silent realclean )) if -e 'Makefile';

    foreach my $step (@build_commands) {
        my $status = _run_command(@$step);

        if ($status) {
            report_unexpected_failure(\@configuration, $status)
                unless expected_failure(\@configuration);

            # can't proceed any further, so give up.  (though some errors might
            # be recoverable, just by redoing.  in fact, just retrying could be
            # a cheap way to distinguish them!  that's probably a different job
            # though.)
            return;
        }
    }

    report_unexpected_success(\@configuration)
        if expected_failure(\@configuration);

    return;
}


# returns true if the set of parrot configuration options is known to be
# problematic.
sub expected_failure
{
    my ($configuration) = @_;

#    return true if $config is a superset of any known failure
#    FIXME should check that the error output matches an appropriate pattern?
    return 1 if (   '--cc=clang' ~~ $configuration
                and '--optimize' ~~ $configuration);

    return 0;
}


# prints a hopefully useful message about an unexpected failure.
#
# takes a reference to the configuration options array, and the status hashref
# returned by _run_command.  returns nothing.
sub report_unexpected_failure
{
    my ($configuration, $status) = @_;

    say '#' x 80;
    say "'$status->{command}' exited with status $status->{exit}/$status->{signal}.\n";
    say ${$status->{output}};

    say "Error running configuration: '@$configuration'";
    say '#' x 80;

    return;
}


# prints a hopefully useful (and cheering) message about an unexpected success.
#
# takes a reference to the configuratiopn options array.  returns nothing.
sub report_unexpected_success
{
    my ($configuration) = @_;

    say '#' x 80;
    say "Configuration '@$configuration' unexpectedly succeeded.\n";
    say '#' x 80;

    return;
}


sub main
{
    # load the config
    my $config = load_config();

    local $ENV{TEST_JOBS}       = $config->{test_jobs};
    local $ENV{HARNESS_VERBOSE} = $config->{harness_verbosity};

    set_limits($config->{priority}, $config->{limits});

    # fetch the configurations to test
    my @configurations = parrot_configs($config);

    test_configuration($config, $_) foreach @configurations;

    return 0;
}


exit main(@ARGV) unless caller;


# vim: sw=4 : ts=4 : et
