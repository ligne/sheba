package Sheba::Tester;

#
# Tests various configurations of the Parrot in the current directory.
#

use strict;
use warnings;

use 5.10.0;

use List::PowerSet qw( powerset );
use Tie::Pick;

use Sheba::Builder;


# the standard list of configurations to test.
my @standard_configurations = (
    [qw(                   --optimize? )],
    [qw( --cc=g++   --link=g++   --ld=g++ )],
    [qw( --cc=clang --link=clang --ld=clang )],
    [qw( --without-gmp     --optimize? )],
    [qw( --without-icu     --optimize? )],
    [qw( --without-libffi  --optimize? )],
    [qw( --without-zlib    --optimize? )],
    [qw( --without-threads --optimize? )],
    [qw( --without-gettext --without-gmp --without-libffi --without-extra-nci-thunks --without-opengl --without-readline --without-pcre --without-zlib --without-threads --without-icu --optimize? )],
    ('random') x 3,
);


# a (more or less) exhaustive list of options that can be passed to
# Configure.pl
my @options_list = (
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
    ),
);


my %config = (
    test_jobs         =>  6,
    harness_verbosity => -2,
);


# a constructor.  what did you expect? ;-)
sub new { return bless {}, (shift) }


# List of configs to test.  each element is an arrayref that will be passed to
# Configure.pl, or the string 'random', which will be replaced with a randomly
# generated group of options.
#
# FIXME it's actually random now, but only at the cost of evil gut-poking
sub configuration_list
{
    my ($self) = @_;

    $self->{random_config_generator} ||= random_config_generator(@options_list);
    return map { $self->_expand_configuration($_) } @standard_configurations;
}


# convert a configuration as specified above, into something that can be fed to
# Configure.pl.  Can currently handle:
#
# + just a hashref (returns it directly)
# + if an item ends in a question mark, two configs are returned:  one with,
#   and one without
# + if it's the string 'random', it returns a randomly generated configuration.
#
# always returns a list of one or more hashrefs.
sub _expand_configuration
{
    my ($self, $config) = @_;

    return
        $config eq 'random' ? Tie::Pick::FETCH($self->{random_config_generator}) :
        $config ~~ qr(\?)   ? ([ grep !m{\?}, @$config ], [ map { s/\?//; $_ } @$config ])               :
                              $config                                            ;
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


# loads the configuration list, and tests each of them in turn.
sub run_tests
{
    my ($self) = @_;

    $self->test_configuration($_) foreach $self->configuration_list;

    return;
}


# takes an arrayref with a set of configure options, and tests it.  reports any
# problems to stdout.
sub test_configuration
{
    my ($self, $configuration) = @_;

    my @configuration = _flatten(@$configuration);

    # FIXME not a great place to put it...
    local $ENV{TEST_JOBS}       = $config{test_jobs};
    local $ENV{HARNESS_VERBOSE} = $config{harness_verbosity};

    # FIXME this is quite ugly...
    my @build_commands = (
        [qw( perl Configure.pl --silent ), @configuration ],
        [qw( make --silent ) ],  # FIXME make_jobs
        [qw( make --silent test )],
    );

    Sheba::Builder::run_command(qw( make --silent realclean )) if -e 'Makefile';

    foreach my $step (@build_commands) {
        my $status = Sheba::Builder::run_command(@$step);

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

    return;
}


# prints a hopefully useful (and cheering) message about an unexpected success.
#
# takes a reference to the configuration options array.  returns nothing.
sub report_unexpected_success
{
    my ($configuration) = @_;

    say '#' x 80;
    say "Configuration '@$configuration' unexpectedly succeeded.\n";

    return;
}


1;
# vim: sw=4 : ts=4 : et
