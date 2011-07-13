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
use BSD::Resource;

use Sheba::Builder;


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
    run sub { Sheba::Builder::set_limits(10); report_limits() }, '&>', \(my $output);

    my %limits = split m{\n|(?: = )}, $output;

    eq_or_diff($limits{priority}, 10, 'increased the niceness') or diag($output);
}
{
    run sub {
        Sheba::Builder::set_limits(undef, { cpu => 600 });
        report_limits()
    }, '&>', \(my $output);

    my %limits = split m{\n|(?: = )}, $output;

    eq_or_diff($limits{RLIMIT_CPU}, 600, 'limited the CPU time') or diag($output);
}
{
    run sub {
        Sheba::Builder::set_limits(undef, { as => 10 });
        report_limits();
        my $str = 'x' x 1e6;  # 1MB should be enough to trigger this
        exit 0;
    }, '&>', \(my $output);

    ok($?, 'subprocess was killed due to too much memory usage');
}
{
    run sub {
        Sheba::Builder::set_limits(undef, { blahblah => 600 });
        report_limits()
    }, '&>', \(my $output);

    like($output, qr('blahblah' is not supported), 'error when setting an unknown limit');
}


### _run_command
{
    ok(! Sheba::Builder::run_command('perl', '-E', 'say "blah"; say STDERR "blah"; exit 0'), 'nothing is returned on success');
    eq_or_diff(
        Sheba::Builder::run_command('perl', '-E', 'say "blah"; say STDERR "blah"; exit 1'),
        {
            command => 'perl -E say "blah"; say STDERR "blah"; exit 1',
            exit    => 1,
            signal  => 0,
            output  => \"blah\nblah\n",
        },
        'many things are returned on failure'
    );
};




done_testing();
