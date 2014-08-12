use strict;
use warnings;

use lib qw(/home/cindy/perl5/lib/perl);
use B::Deparse;

use DestructAssign qw(des des_alias);
use Carp;
use Data::Dumper;
$Data::Dumper::Indent = 0;
$Carp::MaxArgLen = 0;
$Carp::MaxArgNums = 0;

BEGIN {
    $SIG{__DIE__} = sub { confess $_[0] };
}

our $y;

sub tt($) : lvalue {}

#{
#    my($x, $z, $q, $g, @remain, %hv, $o);
#    tt [[$x, 2 => $y, { a => $z, b => $A::o }, @A::X, %B::Y, \%hv, \$y, \$x, [$x]], {a => $q}];
#}

# 預期用法
# {
#    my($a, $b, $c);
#    des [$a, {b => $b, c => [undef, $c]] = [1, {a => 'a', b => [1,2,3], c => [5, 6]];
#    # 得到
#    # $a = 1
#    # $b = [1,2,3]
#    # $c = 6
# }
# array 加上 jump index
# {
#    my($a, $b, $c, $d);
#    des [$a, 2, $b, $c, 9, $d] = [0, 1, 2, 3, 4]
#    # 得到
#    # $a = 0
#    # $b = 2
#    # $c = 3
#    # $d = undef
# }
# 順便幫忙 my
# {
#    des_my [$a, {b => $b, c => [undef, $c]] = [1, {a => 'a', b => [1,2,3], c => [5, 6]];
#    # 得到 (而且都自動加上 lexical 宣告)
#    # $a = 1
#    # $b = [1,2,3]
#    # $c = 6
# }
# alias 型式
# {
#    my $data = [1, {a => 'a', b => [1,2,3], c => [5, 6]];
#
#    des_my_alias [$a, {b => $b, c => [undef, $c]] = $data;
#    # or
#    my ($a, $b, $c);
#    des_alias [$a, {b => $b, c => [undef, $c]] = $data;
#
#    $a = 2; $b = { b => 'b' }; $c = 'oo';
#    # 得到
#    # $data = [2, {a => 'a', b => {b => 'b'}, c => [5, 'oo']];
# }

sub f {
    my($q, $g, @remain, %hv, $o);
    des [my $x, $y, my $z] = \@_;
    print "\$x=$x \$y=$y \$z=$z\n";
    des [undef, $x, -2 => $z, [$y]] = [3, 4, 5, [6], 8, [7]];
    print "\$x=$x \$y=$y \$z=$z\n";
    des {x => $x, y => $y} = {x => 'x', y => 'y'};
    print "\$x=$x \$y=$y \$z=$z\n";
    @remain = ('a'..'c');
    des [$x, {oo => [$A::o]}, -5 => @remain, -5 => %hv, -5 => @A::array, -4 => %A::hash] = ['x', {oo => ['Ao']}, 1..9];
    print "\$x=$x \$A::o=$A::o \@remain=@remain \@A::array=@A::array\n";
    local $Data::Dumper::Indent = 0;
    print '%hv=', Dumper(\%hv), $/;
    print '%A::hash=', Dumper(\%A::hash), $/;
    #des [ *main::yy ] = [sub { print "yy\n" }];

    #yy();
}

BEGIN {
    my $depth = 0;
    my $silent = 0;
    for my $entry ( keys %B::Deparse:: ) {
        no strict 'refs';
        if( my $f = *{"B::Deparse\::$entry"}{CODE} ) {
            no warnings 'redefine';
            no warnings 'prototype';
            *{"B::Deparse\::$entry"} = sub {
                if( $silent ) {
                    return &$f;
                }
                if( grep { $entry eq $_ } qw(pessimise class null is_state is_scope is_miniwhile is_for_loop) ) {
                    my $ori_silent = $silent;
                    $silent = 1;
                    if( wantarray ) {
                        my @res = &$f;
                        $silent = $ori_silent;
                        return @res;
                    } elsif( defined wantarray ) {
                        my $res = &$f;
                        $silent = $ori_silent;
                        return $res;
                    } else {
                        &$f;
                        $silent = $ori_silent;
                        return;
                    }
                }
                my($package, $filename, $line) = caller;
                for (1..$depth) {
                    print " ";
                }
                local $" = ',';
                print "> $entry(@_) from $filename:$line\n";
                ++$depth;
                my $leave = sub {
                    --$depth;
                    for (1..$depth) {
                        print " ";
                    }
                    if( defined $_[0] ) {
                        print "< $entry -> ($_[0])\n";
                    } else {
                        print "< $entry\n";
                    }
                };

                if( wantarray ) {
                    my @res = &$f;
                    if( $entry eq 'gv_name' || $entry eq 'padname' || $entry eq 'const' ) {
                        $leave->($res[0]);
                    } else {
                        $leave->();
                    }
                    return @res;
                } elsif( defined wantarray ) {
                    my $res = &$f;
                    if( $entry eq 'padname_sv' || $entry eq 'gv_name' || $entry eq 'padname' || $entry eq 'const' ) {
                        $leave->($res);
                    } else {
                        $leave->();
                    }
                    return $res;
                } else {
                    &$f;
                    $leave->();
                    return;
                }
            };
        }
    }

    #print B::Deparse->new('-p', '-P')->coderef2text(\&f),$/;
}

f(qw(X Y Z));

{
    my $data = [1, {x => [2,3,4], y => 6}, 3];
    des_alias [my $a, {y => my $b, x => [2 => my $c]}] = $data;
    print '$data=', Dumper($data), $/;
    print "\$a=$a, \$b=$b, \$c=$c\n";
    ($a, $b, $c) = (4, 5, 6);
    print '$data=', Dumper($data), $/;
}

{
    des [my($a, $b), {a => my $c}] = [1,2,{a => 3}];
    print "$a $b $c\n";
}
