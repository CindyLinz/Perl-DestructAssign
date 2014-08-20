# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl DestructAssign.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use Test::More tests => 25;
BEGIN { use_ok('DestructAssign') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

# Synopsis
{
  my($w, $x, $y, $z);
  DestructAssign::des [$x, [undef, {y => $y}, undef, $w], $z] = [2, [25, {x => 'x', y => 3}, 26, 1], 4];
  is_deeply [$w, $x, $y, $z], [1, 2, 3, 4], 'Synopsis1';
  # (use undef as the skipping placeholder)

  # put skip index in the list pattern
  DestructAssign::des [3 => $w, $x, -2 => $y, $z] = [1..9];
  is_deeply [$w, $x, $y, $z], [4, 5, 8, 9], 'Synopsis2';

  # put @array or @hash in the list pattern to eat all the remaining element
  my(@array, %hash);
  DestructAssign::des [3 => @array, -4 => %hash] = [1..8];
  is_deeply [\@array, \%hash], [[4..8], {5..8}], 'Synopsis3';

  # put the same index or hash key
  #  when you need to capture different granularity on the same data structure
  DestructAssign::des {x => $x, x => [$y, $z]} = {x => [1, 2]};
  is_deeply [$x, $y, $z], [[1,2], 1, 2], 'Synopsis4';

  # use the alias semantics
  my $data = [1, 2, 3];
  DestructAssign::des_alias [undef, $x] = $data;
  $x = 20;
  is_deeply $data, [1, 20, 3], 'Synopsis5';
}

# mix des with my/local
{
    my $a = 5;
    our $y = 7;
    {
        DestructAssign::des [my $a] = [10];
        is($a, 10, 'new my');
        DestructAssign::des [local $y] = [11];
        is($y, 11, 'new local');
    }
    is($a, 5, 'orig my');
    is($y, 7, 'orig our');
}

# mix des_alias with my/local
{
    my $data = [10];
    my $a = 5;
    our $y = 7;
    {
        DestructAssign::des_alias [my $a] = $data;
        is($a, 10, 'new my');
        $a = 11;
        is($data->[0], 11, 'alter by des_alias my');
        DestructAssign::des_alias [local $y] = $data;
        is($y, 11, 'new local');
        $y = 12;
        is($data->[0], 12, 'alter by des_alias local');
    }
    is($a, 5, 'orig my');
    $a = 6;
    is($data->[0], 12, 'unchange by orig my');
    is($y, 7, 'orig our');
    $y = 8;
    is($data->[0], 12, 'unchange by orig our');
}

# two vars alias same field
{
    my $data = [5];
    DestructAssign::des_alias [my $a, 0 => my $b] = $data;
    $a = 6;
    is($data->[0], 6, 'data change by a');
    is($a, 6, 'a change by a');
    is($b, 6, 'b change by a');
    $b = 7;
    is($data->[0], 7, 'data change by b');
    is($a, 7, 'a change by b');
    is($b, 7, 'b change by b');
}

# to fix bug
{
    my $a;
    DestructAssign::des [[$a]] = [[1]];
    is($a, 1, 'bug fix');
}
