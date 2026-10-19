package TMS::Adapter::VueI18n;
use Mojo::Base -base, -signatures;
use Role::Tiny;

with 'TMS::Adapter::Role';
with 'TMS::Adapter::Nested';

use Mojo::JSON qw(decode_json);

sub name      { 'vue' }
sub extension { 'json' }

sub parse ($self, $content) {
  die "VueI18n: content is not a string\n" unless defined $content;
  my $tree = eval { decode_json($content) };
  die "VueI18n: invalid JSON: $@" unless defined $tree;
  die "VueI18n: expected a JSON object at the top level\n"
    unless ref $tree eq 'HASH';
  return $self->flatten_node($tree, '');
}

sub serialize ($self, $hash) {
  die "VueI18n: expected a hashref\n" unless ref $hash eq 'HASH';
  my $tree = $self->nest_flat($hash);
  return _encode_sorted($tree, 0) . "\n";
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
