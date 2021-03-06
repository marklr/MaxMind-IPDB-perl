package MaxMind::IPDB::Metadata;

use strict;
use warnings;
use namespace::autoclean;

use Math::BigInt;

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::StrictConstructor;

{
    class_type('Math::BigInt');

    my %metadata = (
        binary_format_major_version => 'Int',
        binary_format_minor_version => 'Int',
        build_epoch                 => 'Int|Math::BigInt',
        database_type               => 'Str',
        description                 => 'HashRef[Str]',
        ip_version                  => 'Int',
        node_count                  => 'Int',
        record_size                 => 'Int',
    );

    for my $attr ( keys %metadata ) {
        has $attr => (
            is       => 'ro',
            isa      => $metadata{$attr},
            required => 1,
        );
    }
}

has languages => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { [] },
);

sub metadata_to_encode {
    my $self = shift;

    my %metadata;
    foreach my $attr ( $self->meta()->get_all_attributes() ) {
        my $method = $attr->name;
        $metadata{$method} = $self->$method;
    }

    return \%metadata;
}

__PACKAGE__->meta()->make_immutable();

1;
