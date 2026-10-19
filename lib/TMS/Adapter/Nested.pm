package TMS::Adapter::Nested;
use Mojo::Base -role, -signatures;

sub flatten_node ($self, $node, $prefix = '') {
  if (ref $node eq 'HASH') {
    my %out;
    for my $k (sort keys %$node) {
      my $sub_prefix = length $prefix ? "$prefix.$k" : $k;
      %out = (%out, %{ $self->flatten_node($node->{$k}, $sub_prefix) });
    }
    return \%out;
  }
  if (ref $node eq 'ARRAY') {
    my %out;
    my $i = 0;
    for my $v (@$node) {
      my $sub_prefix = length $prefix ? "$prefix.$i" : "$i";
      %out = (%out, %{ $self->flatten_node($v, $sub_prefix) });
      $i++;
    }
    return \%out;
  }
  return { $prefix => defined $node ? "$node" : '' };
}

sub nest_flat ($self, $hash) {
  my %root;
  for my $key (keys %$hash) {
    my @parts = split /\./, $key, -1;
    my $ref = \%root;
    while (@parts > 1) {
      my $p = shift @parts;
      $ref->{$p} = {} unless ref $ref->{$p} eq 'HASH';
      $ref = $ref->{$p};
    }
    $ref->{ $parts[0] } = $hash->{$key};
  }
  return \%root;
}

1;
