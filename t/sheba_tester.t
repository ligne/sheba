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

use Sheba::Tester;

use constant HAVE_TEST_OUTPUT => eval {
    require Test::Output;
};


### new
new_ok('Sheba::Tester');


### configuration_list
=cut
{
    my $tester = Sheba::Tester->new();

    {
        my @configs = $tester->configuration_list();
        eq_or_diff($configs[0], [ qw( --optimize --without-gmp )], 'static config only');

        $tester->{$tester->configuration_list} = [
            [qw( --optimize --without-gmp )],
            ('random') x 2,
        ];
    }
    {
        my @configs = $tester->configuration_list();
        is(scalar @configs, 3, 'got 3 configs') or next;
        eq_or_diff($configs[0], [ qw( --optimize --without-gmp )], 'static config is first');

        is("@{$configs[1]}", "@{$configs[1]}", 'the random configuration is equal to ittester (sanity check)');
        isnt("@{$configs[1]}", "@{$configs[2]}", 'the random configurations are different');
    }
}
=cut


### random_config_generator
{
    ok(Sheba::Tester::random_config_generator(qw( 1 2 3 )), 'returns a generator thing');
    # FIXME actually do something with this?
}

### _flatten
eq_or_diff([ Sheba::Tester::_flatten(1, 2, 3) ],    [ 1, 2, 3], 'flat list');
eq_or_diff([ Sheba::Tester::_flatten(1, [ 2, 3]) ], [ 1, 2, 3], 'nested list');


### run_tests

### test_configuration
=cut
{
    my @_run_command_args;

    {
        no warnings 'redefine';
        local *_run_command = sub { push @_run_command_args, \@_; return };

        # FIXME this is horribly fragile...
        @_run_command_args = ();
        test_configuration($config, [
            [qw( --cc=g++ --link=g++ --ld=g++ )],
            '--optimize'
        ]);

        is_deeply(\@_run_command_args, [
            [qw( make realclean --silent )],
            [qw( perl Configure.pl --silent --cc=g++ --link=g++ --ld=g++ --optimize )],
            [qw( make --silent ), "-j6" ],
            [qw( make --silent test )],
        ], 'test an empty config');
    }
}
=cut


### expected_failure


### report_unexpected_failure
SKIP: {
    skip 'Test::Output is required for these tests', 1 unless HAVE_TEST_OUTPUT;

    my $tester = Sheba::Tester->new();

    Test::Output::combined_is {
        Sheba::Tester::report_unexpected_failure([qw( --optimize --without-libffi )], {
            command => 'make test',
            exit    => 23,
            signal  => 11,  # realism!
            output  => \'Segmentation fault (core dumped)',
        })
    } q{
################################################################################
'make test' exited with status 0/11.
Segmentation fault (core dumped)

Error running configuration: '--optimize --without-libffi'},
    'report all output on failure';
};


### report_unexpected_success
SKIP: {
    skip 'Test::Output is required for these tests', 1 unless HAVE_TEST_OUTPUT;

    my $tester = Sheba::Tester->new();

    Test::Output::combined_is {
        Sheba::Tester::report_unexpected_success([qw( --optimize --without-libffi )])
    } q{
################################################################################
Configuration '--optimize --without-libffi' unexpectedly succeeded.},
    'report an unexpected success';
};


done_testing();
