# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl DestructAssign.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use Test::More tests => 6;
BEGIN { use_ok('DestructAssign') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

# Synopsis
{
  my($w, $x, $y, $z);
  DestructAssign::des [$x, [undef, {y => $y}, undef, $w], $z] = [2, [25, {x => 'x', y => 3}, 26, 1], 4];
  is_deeply [$w, $x, $y, $z], [1, 2, 3, 4];
  # (use undef as the skipping placeholder)

  # put skip index in the list pattern
  DestructAssign::des [3 => $w, $x, -2 => $y, $z] = [1..9];
  is_deeply [$w, $x, $y, $z], [4, 5, 8, 9];

  # put @array or @hash in the list pattern to eat all the remaining element
  my(@array, %hash);
  DestructAssign::des [3 => @array, -4 => %hash] = [1..8];
  is_deeply [\@array, \%hash], [[4..8], {5..8}];

  # put the same index or hash key
  #  when you need to capture different granularity on the same data structure
  DestructAssign::des {x => $x, x => [$y, $z]} = {x => [1, 2]};
  is_deeply [$x, $y, $z], [[1,2], 1, 2];

  # use the alias semantics
  my $data = [1, 2, 3];
  DestructAssign::des_alias [undef, $x] = $data;
  $x = 20;
  is_deeply $data, [1, 20, 3];
}
