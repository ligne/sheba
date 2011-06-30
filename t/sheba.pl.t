# vim: sw=4 : ts=4 : et
use strict;
use warnings;

use 5.10.0;

use lib 't/lib';

use Test::More;
use Test::Deep;
use Test::Differences;
use Test::LongString;

use Data::Dumper;
use IPC::Run qw( run );


use constant HAVE_TEST_OUTPUT => eval {
    require Test::Output;
};

require 'bin/sheba.pl';


### parrot_configs


### random_config_generator
{
    ok(random_config_generator(qw( 1 2 3 )), 'returns a generator thing');
    # FIXME actually do something with this?
}


### _flatten
eq_or_diff([ _flatten(1, 2, 3) ],    [ 1, 2, 3]);
eq_or_diff([ _flatten(1, [ 2, 3]) ], [ 1, 2, 3]);


### set_limits

# helper:  prints the current priority and limits to stdout.
sub report_limits
{
    say "priority = ", getpriority(0, 0);

    my $rlimits = get_rlimits();

    while (my ($name, $resource) = each %$rlimits) {
        say "$name = ", scalar getrlimit($resource);
    }
}

# TODO test with Module::Mask

{
    run sub { set_limits(10); report_limits() }, '&>', \(my $output);

    my %limits = split m{\n|(?: = )}, $output;

    eq_or_diff($limits{priority}, 10, 'increased the niceness') or diag($output);
}
{
    run sub {
        set_limits(undef, { cpu => 600 });
        report_limits()
    }, '&>', \(my $output);

    my %limits = split m{\n|(?: = )}, $output;

    eq_or_diff($limits{RLIMIT_CPU}, 600, 'limited the CPU time') or diag($output);
}


### _run_command
my @perl = qw( perl -E );

{
    my @command = 'true';
    ok(_run_command(@command), 'command succeeded');
    ok(_run_command(@command, { todo => 1 }), 'command unexpectedly succeeded');
}
{
    my @command = 'false';
    ok(! _run_command(@command), 'command failed');
    ok(! _run_command(@command, { todo => 1 }), 'command failed as expected');
}

SKIP: {
    skip 'Test::Output is required for these tests', 3 unless HAVE_TEST_OUTPUT;

    # boring

    Test::Output::combined_is {
        _run_command(@perl, 'say "blah"; say STDERR "blah"; exit 0')
    } '', 'quiet on success';

    Test::Output::combined_like {
        _run_command(@perl, 'say "blah"; say STDERR "blah"; exit 1')
    } qr(blah\nblah), 'report all output on failure';


    # todo
    Test::Output::combined_is {
        _run_command(@perl, 'say "blah"; say STDERR "blah"; exit 1', { todo => 1 })
    } '', 'quiet on expected failure';

    Test::Output::stdout_like {
        _run_command(qw( perl -E 1 ), { todo => 1 })
    } qr(unexpectedly), 'warning on unexpected success';
};


done_testing();
