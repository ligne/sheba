package Sheba::Builder;
#
# Builds the Parrot in the current directory.
#

use strict;
use warnings;

use 5.10.0;

use IPC::Run       qw( run );
use BSD::Resource;


# returns a config hash thing
my @settings = (
    make_jobs => 6,
    test_jobs => 6,

    harness_verbosity => -2,

    priority => 10,   # niceness
    limits => {
        # see BSD::Resource docs for details
        cpu      => 600,  # cpu time in seconds
        as       => 1e9,  # memory usage (stack, heap, et al.)
    },
);


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
sub run_command
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


1;
# vim: sw=4 : ts=4 : et
