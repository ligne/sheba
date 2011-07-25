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

use constant HAVE_TEST_OUTPUT       => eval { require Test::Output       };
use constant HAVE_DIRECTORY_SCRATCH => eval { require Directory::Scratch };

### new
new_ok('Sheba::Tester');


### deduce_options
{
    my $defaults = [
        [qw( --one --two --three )],
        '--four',
    ];

    my $tester = Sheba::Tester->new(
        options_list => $defaults,
    );

    eq_or_diff(
        [ grep { $_ ne '--m=32' } $tester->deduce_options ],
        $defaults,
        'got some defaults'
    );
    ok($tester->{random_config_generator}, 'initialised the random config generator');
}
{
    my $defaults = [
        [qw( --one --two --three )],
        '--four',
    ];

    my $tester = Sheba::Tester->new(
        options_list => $defaults,
    );


    # mmmh, evil...
    my $dir = Directory::Scratch->new();

    $dir->touch('Parrot/Configure/Options/Conf/Shared.pm', <<'EOT');
package Parrot::Configure::Options::Conf::Shared;

our @shared_valid_options = qw(
    five
    without-six
    without-seven
    without-eight
);

1;
EOT

    $dir->touch('Parrot/Config.pm', <<'EOT');
package Parrot::Config;

our %PConfig = (
    has_six   => 1,  # if it exists, we can turn it off
    has_seven => 0,  # not supported anyway
                     # has_eight isn't mentioned at all
);

1;
EOT

    local @INC = ("$dir", @INC);

    eq_or_diff([ grep { $_ ne '--m=32' } $tester->deduce_options ], [
        @$defaults,
        qw( --without-six --without-eight ),
    ], 'identified some extra options');

    ok($tester->{random_config_generator}, 'initialised the random config generator');
}


### next_configuration
{
    my $tester = Sheba::Tester->new(
        configurations => [
            [],
            [qw( --without-gmp --optimize  )],
            [qw( --without-icu --optimize? )],
            'random',
        ],
    );

    my @expected = (
        [],
        [qw( --without-gmp --optimize )],
        [qw( --without-icu )],
        [qw( --without-icu --optimize )],
    );

    foreach (@expected) {
        eq_or_diff($tester->next_configuration, $_, 'got a config');
    }

    is(ref $tester->next_configuration, 'ARRAY', 'random config got inflated');

    ok(! $tester->next_configuration, 'no more configs');
}


### random_config_generator
{
    ok(Sheba::Tester::random_config_generator(), 'returns a generator thing');
    # FIXME actually do something with this?
}


### _flatten
eq_or_diff([ Sheba::Tester::_flatten(1, 2, 3) ],    [ 1, 2, 3], 'flat list');
eq_or_diff([ Sheba::Tester::_flatten(1, [ 2, 3]) ], [ 1, 2, 3], 'nested list');


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
