package Sheba::Repository;

# handles the cached (and possibly test) clones of the project.

use strict;
use warnings;

use 5.10.0;

use Git;
use File::Spec ();
use File::Temp qw( tempdir );


# yeah, another constructor.
sub new
{
    my ($class, %args) = @_;

    return bless {
        repository => 'git://github.com/parrot/parrot.git',  # the upstream repository
        clone      => '/home/local/mlb/blah',                # a local cached copy

        use_tmpdir => '/dev/shm',
        %args
    }, $class;
}


# prepares a clone for testing, and chdirs there.  returns a handle to the
# repository
sub prepare_repo
{
    my ($self) = @_;

    (my $dir, $self->{test_repo}) = $self->_get_test_repo
        or die "Failed to set up a test repository";

    $self->_get_refs;

    # make sure the repository is up-to-date
    $self->update_repository;

    # chdir to the right place
    chdir $dir or die "Unable to chdir to the test repository: $!";

    return $self->{test_repo};
}


# returns a handle to the clone to run the tests in.
sub _get_test_repo
{
    my ($self) = @_;

    # get the cached clone.  use this one by default...
    my $dir = $self->{clone};
    unless ( -d $dir) {
        # no clone yet, so create one
        system(qw( git clone ), $self->{repository}, $self->{clone}) == 0
            or die "Failed to clone from '$self->{repository}' into '$self->{clone}': $!";
    }

    # ...but if use_tmpdir was set, use a temporary directory.  if it's
    # *actually* a directory, use that as the base.  otherwise whatever the
    # system provides will do.
    if (my $tempdir = $self->{use_tmpdir}) {
        $dir = tempdir(
            CLEANUP => 1,
            -d $tempdir ? (DIR => $tempdir) : (),
        );
        _clone_into($self->{repository}, $dir);
    }

    return Git->repository($dir);
}


# clones the repository at $src into directory $dst.  dies on error
sub _clone_into
{
    my ($src, $dst) = @_;
    system(qw( git clone ), $src, $dst) == 0
        or die "Failed to clone from '$src' into '$dst': $!";
    return;
}


#
sub _get_refs
{
    my ($self) = @_;

    # get the list of old branches.
    $self->{old_branch_heads} = $self->remote_refs(
        $self->{test_repo},
        undef,
        "refs/remotes/$self->{remote_name}/*"
    );
    $self->{new_branch_heads} = $self->remote_refs(
        $self->{repository},
        undef,
        "refs/heads/*"
    );
    return;
}


sub _get_remote_name
{
    my ($self) = @_;

    # get the name of the remote corresponding to the remote we're testing.
    my %remotes = map { m{remote\.(\w+)\.url (.*)}g ? ($2, $1) : () }
        $self->{test_repo}->command("config", "--get-regex", "remote.*.url");

    return $self->{remote_name} = $remotes{$self->{repository}}
        || _add_remote($self->{test_repo}, 'sheba_remote', $self->{repository});
}


# $r->_add_remote($clone, $remote, $name);
# adds a remote called $name to $clone, referencing $remote.
sub _add_remote { (shift)->command(qw( remote add ), (shift), (shift)) }


# fetches changes in the upstream repository into the cached clone
sub update_cached_repository
{
    my ($self) = @_;
    return $self->{test_repo}->command('fetch', $self->remote_name);
}


# checks out the next branch to test.
sub checkout_next_branch
{
    my ($self) = @_;

    my $branch = shift @{$self->{changed_branches}};
    $self->{test_repository}->command(qw( checkout -q --force ), $branch)
        or die "Failed to checkout branch '$branch'";

    return;
}


# work out what branches have changed between the two sets of name => hash
# pairs.
sub _changed_branches
{
    my ($repo, $old, $new) = @_;

    my @branches;

    while (my ($ref, $hash) = each %$new) {
        unless (exists $old->{$ref} and $old->{$ref} eq $hash) {
            say "$ref is now $hash";
            push @branches, $ref;
        }
    }

    return @branches;
}


1;
# vim: sw=4 : ts=4 : et
