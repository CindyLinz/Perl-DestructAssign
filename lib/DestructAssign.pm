package DestructAssign;

use 5.008;
use strict;
use warnings;
use Carp;

require Exporter;
use AutoLoader;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use DestructAssign ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
    des des_alias
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '0.01';

sub des($) : lvalue { ... }
sub des_alias($) : lvalue { ... }

require XSLoader;
XSLoader::load('DestructAssign', $VERSION);

# Preloaded methods go here.

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__

=head1 NAME

DestructAssign - Destructuring assignment

=head1 SYNOPSIS

  use DestructAssign qw(des des_alias);

  my($w, $x, $y, $z);
  des [$x, [undef, {y => $y}, undef, $w], $z] = [2, [25, {x => 'x', y => 3}, 26, 1], 4];
  # got ($w, $x, $y, $z) = (1, 2, 3, 4)
  # (use undef as the skipping placeholder)

  # put skip index in the list pattern
  des [3 => $w, $x, -2 => $y, $z] = [1..9];
  # got ($w, $x, $y, $z) = (4, 5, 8, 9)

  # put @array or @hash in the list pattern to eat all the remaining element
  my(@array, %hash);
  des [3 => @array, -4 => %hash] = [1..8];
  # got @array = (4..8), %hash = (5 => 6, 7 => 8)

  # put the same index or hash key
  #  when you need to capture different granularity on the same data structure
  des {x => $x, x => [$y, $z]} = {x => [1, 2]};
  # got $x = [1,2], $y = 1, $z = 2

  # use the alias semantics
  my $data = [1, 2, 3];
  des_alias [undef, $x] = $data;
  $x = 20;
  # got $data = [1, 20, 3]

  {
    # mixed with lexical variable introduction
    des [my($i, $j), { k => my $k }] = [1, 2, {k => 3}];
    # got my($i, $j, $k) = (1, 2, 3)
  }

=head1 DESCRIPTION

This mod provides destructuring assignment for Perl.
You can capture (by value) or bind (by alias) variables into
part of a potentially large and complex data structure.

I expect it to bring following benefits:

=over 4

=item enhance the performance by avoiding repeatedly digging into complex data structures

Suppose we have data structures like this:

  my $player1 = {
    id => 25,
    hp => 8100,
    armor => {
      body => {
        id => 21,
        name => 'iron suit',
        protect => 10,
        durability => 100,
      },
      hand => {
        id => 29,
        name => 'iron sword',
        attack => 15,
        durability => 100,
      },
    },
  };
  my $player2 = ...;

Instead of

  while( $player1->{hp}>0 && $player2->{hp}>0 ) {
    my $hit1 =
        ($player1->{armor}{hand}{durability} && $player1->{armor}{hand}{attack}) -
        ($player2->{armor}{body}{durability} && $player2->{armor}{body}{protect});
    my $hit2 =
        ($player2->{armor}{hand}{durability} && $player2->{armor}{hand}{attack}) -
        ($player1->{armor}{body}{durability} && $player1->{armor}{body}{protect});
    $hit1 = 1 if( $hit1 <= 0 );
    $hit2 = 1 if( $hit2 <= 0 );

    $player1->{hp} -= $hit2;
    $player2->{hp} -= $hit1;

    --$player1->{armor}{hand}{durability} if( $player1->{armor}{hand}{durability} );
    --$player1->{armor}{body}{durability} if( $player1->{armor}{body}{durability} );
    --$player2->{armor}{hand}{durability} if( $player2->{armor}{hand}{durability} );
    --$player2->{armor}{body}{durability} if( $player2->{armor}{body}{durability} );
  }

We could write

  des_alias [
    {
      hp => my $hp1,
      armor => {
        body => {
          protect => my $protect1,
          durability => my $body_dura1,
        },
        hand => {
          attack => my $attack1,
          durability => my $hand_dura1,
        },
      }
    },
    {
      hp => my $hp2,
      armor => {
        body => {
          protect => my $protect2,
          durability => my $body_dura2,
        },
        hand => {
          attack => my $attack2,
          durability => my $hand_dura2,
        },
      }
    },
  ] = [$data1, $data2];
  
  while( hp1>0 && hp2>0 ) {
    my $hit1 = ($hand_dura1 && $attack1) - ($body_dura2 && $protect2);
    my $hit2 = ($hand_dura2 && $attack2) - ($body_dura1 && $protect1);
    $hit1 = 1 if( $hit1 <= 0 );
    $hit2 = 1 if( $hit2 <= 0 );

    $hp1 -= $hit2;
    $hp2 -= $hit1;

    --$hand_dura1 if( $hand_dura1 );
    --$body_dura1 if( $body_dura1 );
    --$hand_dura2 if( $hand_dura2 );
    --$body_dura2 if( $body_dura2 );
  }

=item enhance the readability by pointing out all the elements you might touch at the begining of each subroutine

It's a good habit to write named parameters instead of access @_ directly
(except you want to modify the caller's arguments).
This mod extend the ability to name parameters in the deep structure.
You can explicitly list all the elements you might touch in the subroutine.

  sub f {
    des [my $x, { id => my $id, amount => my $amount }] = \@_;
    # or use des_alias, if you need to modify the passed parameters.
    des_alias [my $x, { id => my $id, amount => my $amount }] = \@_;
  }

=back

=head2 EXPORT

None by default.

=over 4

=item des pattern = $value

The value semantics of destructuring assignment.

The captured data elements are copied out to the variables.

=item des_alias pattern = $value

The alias semantics of destructuring assignment

The captured data elements are bound to the variables.
After the binding, write to or read from the variables will
affect the bound data.

=back

=head2 PATTERN

The only argument to C<des> or C<des_alias> should be
an anonymous list [..] or anonymous hash {..}.

The elements of them could be

=over 4

=item anonymous list [..]

To match a list reference

=item anonymous hash {..}

To match a hash reference

=item scalar variable $xx

To capture the data element

=item array variable @xx

This can be used only in an anonymous list, not hash.

To capture all the remaining data element of the current array
from current offset.

When using in alias semantics, each element of the array variable will
be bound to data element individually.

=item hash variable %xx

This can be used only in an anonymous list, not hash.

To capture all the remaining data element of the current array
from current offset.

When using in alias semantics, only the values of the hash variable
will be bound to data element, individually.

=item constant undef

When using in an anonymous list, it is used as a skipping placeholder.

When using in an anonymous hash, it is used to set the next capturing key to ''.

=item constant string or number

When using in an anonymous list, we'll take it as a numer to set
the next capturing offset.

When using in an anonymous hash, we'll take it as a string to set
the next capturing key.

=back

=head1 SEE ALSO

This mod's github L<https://github.com/CindyLinz/Perl-DestructAssign>.
It's welcome to discuss with me when you encounter bugs, or
if you think that some patterns are also useful but the mod didn't provide them yet.

I also found a similar mod on github. (no cpan page) L<https://github.com/hirokidaichi/p5-Data-Destructuring-Assignment>
It's implemented in pure Perl with tied structures.
Because it's pure Perl, we need to pass references directly on the left hand side.
It can't take advantage on hash pattern with duplicated keys.
It didn't provide alias semantics either, though it could be added easily if needed.

=head1 AUTHOR

Cindy Wang (CindyLinz)

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 by Cindy Wang (CindyLinz)

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.18.2 or,
at your option, any later version of Perl 5 you may have available.


=cut
