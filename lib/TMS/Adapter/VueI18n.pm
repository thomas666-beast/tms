package TMS::Adapter::VueI18n;
use Mojo::Base -base, -signatures;
use Role::Tiny;

with 'TMS::Adapter::Role';

use Mojo::JSON qw(decode_json);

sub name      { 'vue' }
sub extension { 'json' }

sub parse ($self, $content) {
  die "VueI18n: content is not a string\n" unless defined $content;
  my $tree = eval { decode_json($content) };
  die "VueI18n: invalid JSON: $@" unless defined $tree;
  die "VueI18n: expected a JSON object at the top level\n"
    unless ref $tree eq 'HASH';
  return _flatten($tree, '');
}

sub serialize ($self, $hash) {
  die "VueI18n: expected a hashref\n" unless ref $hash eq 'HASH';
  my $tree = _nest($hash);
  return _encode_sorted($tree, 0) . "\n";
}

sub _flatten ($node, $prefix) {
  if (ref $node eq 'HASH') {
    my %out;
    for my $k (sort keys %$node) {
      my $sub_prefix = length $prefix ? "$prefix.$k" : $k;
      %out = (%out, %{ _flatten($node->{$k}, $sub_prefix) });
    }
    return \%out;
  }
  if (ref $node eq 'ARRAY') {
    my %out;
    my $i = 0;
    for my $v (@$node) {
      my $sub_prefix = length $prefix ? "$prefix.$i" : "$i";
      %out = (%out, %{ _flatten($v, $sub_prefix) });
      $i++;
    }
    return \%out;
  }
  return { $prefix => defined $node ? "$node" : '' };
}

sub _nest ($hash) {
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

sub _encode_sorted ($node, $depth) {
  my $indent = '  ' x $depth;
  my $next   = '  ' x ($depth + 1);

  if (ref $node eq 'HASH') {
    return '{}' unless keys %$node;
    my @lines;
    for my $k (sort keys %$node) {
      my $kj = _json_string($k);
      my $vj = _encode_sorted($node->{$k}, $depth + 1);
      push @lines, "$next$kj: $vj";
    }
    return "{\n" . join(",\n", @lines) . "\n$indent}";
  }

  if (ref $node eq 'ARRAY') {
    return '[]' unless @$node;
    my @lines = map { $next . _encode_sorted($_, $depth + 1) } @$node;
    return "[\n" . join(",\n", @lines) . "\n$indent]";
  }

  return _json_string($node);
}

sub _json_string ($s) {
  $s = '' unless defined $s;
  $s =~ s/\\/\\\\/g;
  $s =~ s/"/\\"/g;
  $s =~ s/\n/\\n/g;
  $s =~ s/\t/\\t/g;
  $s =~ s/\r/\\r/g;
  $s =~ s/([\x00-\x1f])/sprintf '\\u%04x', ord $1/ge;
  return qq{"$s"};
}

1;
