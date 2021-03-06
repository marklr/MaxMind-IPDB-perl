use strict;
use warnings;

use Test::More;

use MaxMind::IPDB::Writer::Tree::InMemory;

use List::AllUtils qw( all );
use MM::Net::IPAddress;
use MM::Net::Subnet;
use Scalar::Util qw( blessed );

# We want to have a unique id as part of the data for various tests
my $id = 0;

{
    my @ipv4_subnets
        = MM::Net::Subnet->range_as_subnets( '1.1.1.1', '1.1.1.32' );

    _test_subnet_permutations( \@ipv4_subnets, 'IPv4' );
}

{
    my @ipv6_subnets = MM::Net::Subnet->range_as_subnets(
        '::1:ffff:ffff',
        '::2:0000:0059'
    );

    _test_subnet_permutations( \@ipv6_subnets, 'IPv6' );
}

{
    my ( $insert, $expect ) = _ranges_to_data(
        [
            [ '1.1.1.0', '1.1.1.15' ],
            [ '1.1.1.1', '1.1.1.32' ],
        ],
        [
            [ '1.1.1.0', '1.1.1.0' ],
            [ '1.1.1.1', '1.1.1.32' ],
        ],
    );

    _test_tree_as_ipv4_and_ipv6(
        $insert, $expect,
        'overlapping subnets - first is lower'
    );
}

{
    my ( $insert, $expect ) = _ranges_to_data(
        [
            [ '1.1.1.0', '1.1.1.15' ],
            [ '1.1.1.14', '1.1.1.32' ],
        ],
        [
            [ '1.1.1.0', '1.1.1.13' ],
            [ '1.1.1.14', '1.1.1.32' ],
        ],
    );

    _test_tree_as_ipv4_and_ipv6(
        $insert, $expect,
        'overlapping subnets - overlap breaks up first subnet into smaller chunks'
    );
}

{
    my ( $insert, $expect ) = _ranges_to_data(
        [
            [ '1.1.1.1', '1.1.1.32' ],
            [ '1.1.1.0', '1.1.1.15' ],
        ],
        [
            [ '1.1.1.0', '1.1.1.15' ],
            [ '1.1.1.16', '1.1.1.32' ],
        ],
    );

    _test_tree_as_ipv4_and_ipv6(
        $insert, $expect,
        'overlapping subnets - first is higher'
    );
}

{
    my ( $insert, $expect ) = _ranges_to_data(
        [
            [ '1.1.1.0', '1.1.1.15' ],
            [ '1.1.1.1', '1.1.1.14' ],
        ],
        [
            [ '1.1.1.0', '1.1.1.0' ],
            [ '1.1.1.1', '1.1.1.14' ],
            [ '1.1.1.15', '1.1.1.15' ],
        ],
    );

    _test_tree_as_ipv4_and_ipv6(
        $insert, $expect,
        'first subnet contains second subnet'
    );
}

{
    my ( $insert, $expect ) = _ranges_to_data(
        [
            [ '1.1.1.1', '1.1.1.14' ],
            [ '1.1.1.0', '1.1.1.15' ],
        ],
        [
            [ '1.1.1.0', '1.1.1.15' ],
        ],
    );

    _test_tree_as_ipv4_and_ipv6(
        $insert, $expect,
        'second subnet contains first subnet'
    );
}

{
    my ( $insert, $expect ) = _ranges_to_data(
        [
            [ '1.1.1.1', '1.1.1.32' ],
        ],
        [
            [ '1.1.1.1', '1.1.1.32' ],
        ],
    );

    my $tree = _make_tree($insert);

    my %saw;
    my @values;
    my $cb = sub {
        my $node_num = shift;
        my $dir      = shift;
        my %p        = @_;

        $saw{"$node_num-$dir"}++;
        push @values, $p{value} if $p{value};

        return;
    };

    $tree->iterate($cb);

    ok(
        ( all { $_ == 1 } values %saw ),
        'each record was visited exactly once'
    );

    is_deeply(
        [ sort { $a->{id} <=> $b->{id} } @values ],
        [
            sort { $a->{id} <=> $b->{id} } map { $_->[1] } @{$expect}
        ],
        'saw expected values for records'
    );
}

done_testing();

sub _test_subnet_permutations {
    my $subnets = shift;
    my $desc    = shift;

    my @expect = map { [ $_, { foo => 42, id => $id++ } ] } @{$subnets};

    {
        # In this case what we insert into the tree matches the order of what
        # we expect
        _test_tree(
            \@expect, \@expect,
            "ordered subnets - $desc"
        );
    }

    {
        my @reversed = reverse @expect;

        _test_tree(
            \@reversed, \@expect,
            "reversed subnets - $desc"
        );
    }

    {
        my @odd  = grep { $_ % 2 } 0 .. $#expect;
        my @even = grep { !( $_ % 2 ) } 0 .. $#expect;

        my @shuffled
            = ( @expect[@odd], @expect[ reverse @even ] );

        _test_tree(
            \@shuffled, \@expect,
            "shuffled subnets - $desc"
        );
    }

    {
        my @duplicated = ( @expect, @expect );

        _test_tree(
            \@duplicated, \@expect,
            "duplicated subnets - $desc"
        );
    }
}

sub _test_tree {
    my $insert_pairs = shift;
    my $expect_pairs = shift;
    my $desc         = shift;

    my $tree = _make_tree($insert_pairs);

    _test_expected_data( $tree, $expect_pairs, $desc );

    for my $raw (qw( 1.1.1.33 8.9.10.11 ffff::1 )) {
        my $address = MM::Net::IPAddress->new(
            address => $raw,
            version => ( $raw =~ /::/ ? 6 : 4 ),
        );

        is(
            $tree->lookup_ip_address($address),
            undef,
            "The address $address is not in the tree - $desc"
        );
    }
}

sub _make_tree {
    my $pairs = shift;

    my $tree = MaxMind::IPDB::Writer::Tree::InMemory->new();

    for my $pair ( @{$pairs} ) {
        my ( $subnet, $data ) = @{$pair};

        $tree->insert_subnet( $subnet, $data );
    }

    return $tree;
}

sub _test_expected_data {
    my $tree   = shift;
    my $expect = shift;
    my $desc   = shift;

    foreach my $pair ( @{$expect} ) {
        my ( $subnet, $data ) = @{$pair};

        my $iter = $subnet->iterator();
        while ( my $address = $iter->() ) {
            is_deeply(
                $tree->lookup_ip_address($address),
                $data,
                "Got expected data for $address - $desc"
            );
        }
    }
}

sub _ranges_to_data {
    my $insert_ranges = shift;
    my $expect_ranges = shift;

    my %ip_to_data;
    my @insert;
    for my $subnet ( map { MM::Net::Subnet->range_as_subnets( @{$_} ), }
        @{$insert_ranges} ) {

        my $data = {
            x  => 'foo',
            id => $id,
        };

        push @insert, [ $subnet, $data ];

        my $iter = $subnet->iterator();
        while ( my $ip = $iter->() ) {
            $ip_to_data{ $ip->as_string() } = $data;
        }

        $id++;
    }

    my @expect = (
        map { [ $_, $ip_to_data{ $_->first()->as_string() } ] } (
            map { MM::Net::Subnet->range_as_subnets( @{$_} ), }
                @{$expect_ranges}
        )
    );

    return \@insert, \@expect;
}

sub _test_tree_as_ipv4_and_ipv6 {
    my $insert = shift;
    my $expect  = shift;
    my $desc    = shift;

    _test_tree( $insert, $expect, $desc );
    _test_tree_as_ipv6( $insert, $expect, $desc );
}

sub _test_tree_as_ipv6 {
    my $insert = shift;
    my $expect = shift;
    my $desc   = shift;

    $insert = [ map { [ _subnet_as_v6( $_->[0] ), $_->[1] ] } @{$insert} ];
    $expect = [ map { [ _subnet_as_v6( $_->[0] ), $_->[1] ] } @{$expect} ];

    _test_tree( $insert, $expect, $desc . ' - IPv6' );
}

sub _subnet_as_v6 {
    my $subnet = shift;

    my $subnet_string
        = '::'
        . $subnet->first()->as_string() . '/'
        . ( $subnet->netmask() + 96 );

    return MM::Net::Subnet->new(
        subnet  => $subnet_string,
        version => 6,
    );
}
