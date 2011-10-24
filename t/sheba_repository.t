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
use File::Temp qw( tmpnam tempdir );
use Cwd;

use Sheba::Repository;


### new
{
    my $r = new_ok('Sheba::Repository');


    $r = Sheba::Repository->new(
        repository => 'git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux-2.6.git',
    );
    is(
        $r->{repository},
        'git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux-2.6.git',
        'was able to set the repository'
    );
}


### _get_clone
=cut
{
    my @git_command_args;
    no warnings 'redefine';
    *Git::command = sub { @git_command_args = @_ };

    my $dir = tmpnam();

    my $repo = Sheba::Repository->new(
        clone => $dir,
        repository => 'git@github.com:ligne/sheba.git',
    );

    my $handle = $repo->_get_clone;

    is($dir, $handle->repo_path, '_get_clone returns the clone directory');
    eq_or_diff(\@git_command_args, [ 'clone', 'git@github.com:ligne/sheba.git', $dir ]);
}
{
    my $dir = tmpnam();

    my $repo = Sheba::Repository->new(
        clone      => $dir,
        repository => cwd(),
    );

    my $handle = $repo->_get_clone;

    is($handle->repo_path, "$dir/.git", '_get_clone returns the clone directory');
    ok( -e $handle->repo_path);
}
=cut


### prepare_repo
{
    # use the main clone

    my $dir = tmpnam();
    my $repo = Sheba::Repository->new(
        clone      => $dir,
        repository => '.',
    );

    delete $repo->{use_tmpdir};

    my $r = $repo->prepare_repo;
    is($r->repo_path, "$dir/.git", 'new clone was created');
}
{
    # use any temporary directory

    my $dir = tmpnam();
    my $repo = Sheba::Repository->new(
        clone      => $dir,
        repository => '.',
        use_tmpdir => 1,
    );

    my $r = $repo->prepare_repo;
    isnt($r->repo_path, "$dir/.git", 'the test repo is in a temporary directory');
}
{
    # use a specific temporary directory

    my $dir = tmpnam();
    my $dir1 = tempdir();

    my $repo = Sheba::Repository->new(
        clone      => $dir,
        repository => '.',
        use_tmpdir => $dir1,
    );

    my $r = $repo->prepare_repo;
    like($r->repo_path, qr(^\Q$repo->{use_tmpdir}\E/), 'the test repo is a subdirectory of use_tmpdir');
}


### remote_name
{
    my $dir = tmpnam();

    my $repo = Sheba::Repository->new(
        clone => $dir,
        repository => '',
    );

    $repo->{test_repo} = Git->repository();

    is($repo->remote_name, '');
}



done_testing();
