package Sheba::Tester;

#
# Tests various configurations of the Parrot in the current directory.
#

use strict;
use warnings;

use 5.10.0;

use List::PowerSet qw( powerset );
use Tie::Pick;
use Config;

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


# options that can be passed to Configure.pl, but which can't easily be
# extracted automatically
my @options_list = (
    [qw( --cc=clang --link=clang --ld=clang )],
    [qw( --cc=g++ --link=g++ --ld=g++ )],
    qw( --optimize ),
);


# a constructor.  what did you expect? ;-)
sub new
{
    my ($class, %args) = @_;

    return bless {
        options_list   => \@options_list,
        configurations => [@standard_configurations],

        test_jobs         =>  6,
        harness_verbosity => -2,

        %args,
    }, $class;
}


# tries to work out what options Parrot's Configure.pl currently supports, and
# which actually have an effect on the build (ie. isn't disabled by default due
# to missing dependencies).  uses that information to initialise the random
# config generator.
sub deduce_options
{
    my ($self) = @_;

    return if $self->{random_config_generator};  # already done this

    my @all_options = @{$self->{options_list}};

    eval {
        require Parrot::Configure::Options::Conf::Shared;
        require Parrot::Config;

        # remove any --without-* options that aren't supported
        foreach my $opt (@Parrot::Configure::Options::Conf::Shared::shared_valid_options) {
            my ($n) = ($opt =~ m{^without-(\w+)}) or next;

            # ignore it if it's been found to be missing (but err on the
            # generous side).
            next if exists $Parrot::Config::PConfig{"has_$n"}
                and    not $Parrot::Config::PConfig{"has_$n"};

            push @all_options, "--$opt";
        }
    };

    # if it's 64-bit
    # FIXME currently bombs out with linker errors.
#    push @all_options, '--m=32' if $Config{ptrsize} == 8;

    $self->{random_config_generator} = random_config_generator(@all_options);

    return @all_options;
}


# returns a tied scalar that pops out a random arrayref of configuration
# options picked from the arguments.
sub random_config_generator
{
    tie my $ps => 'Tie::Pick' => powerset(@_);
    return $ps;
}


# returns an arrayref representing the next configuration to test.
#
# Configurations can be specified as any of the following:
# + just a hashref (returns it directly)
# + if an item ends in a question mark, two configs will be generated:  one with,
#   and one without
# + if it's the string 'random', it returns a randomly generated configuration.
sub next_configuration
{
    my ($self) = @_;

    my $next_config = shift @{$self->{configurations}} or return;
    my $config;

    given ($next_config) {
        when ('random') {
            $self->deduce_options;
            $config = Tie::Pick::FETCH($self->{random_config_generator});
        }
        when (qr(\?)) {
            # queue the "with" config up for next time, and return the
            # "without" config now.
            $config = [ grep !m{\?}, @$next_config ];
            unshift @{$self->{configurations}}, [ map { s/\?//; $_ } @$next_config ];
        }
        default {
            $config = $next_config;
        }
    }

    return $config;
}


# flattens a list
sub _flatten { return map { ref eq 'ARRAY' ? @$_ : $_ } @_ }


# loads the configuration list, and tests each of them in turn.
sub run_tests
{
    my ($self) = @_;

    while (my $c = $self->next_configuration) {
        $self->test_configuration($c);
    }

    return;
}


# takes an arrayref with a set of configure options, and tests it.  reports any
# problems to stdout.
sub test_configuration
{
    my ($self, $configuration) = @_;

    my @configuration = _flatten(@$configuration);

    say "Testing configuration '@configuration'";

    # FIXME not a great place to put it...
    local $ENV{TEST_JOBS}       = $self->{test_jobs};
    local $ENV{HARNESS_VERBOSE} = $self->{harness_verbosity};

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
