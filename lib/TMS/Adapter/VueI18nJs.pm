package TMS::Adapter::VueI18nJs;
use Mojo::Base -base, -signatures;
use Role::Tiny;

with 'TMS::Adapter::Role';
with 'TMS::Adapter::Nested';

sub name      { 'vue_js' }
sub extension { 'js' }

sub parse ($self, $content) {
  die "VueI18nJs: content is not a string\n" unless defined $content;

  my $body = $content;
  $body =~ s/^\x{FEFF}//;
  $body =~ s{/\*.*?\*/}{}gs;
  $body =~ s{(?<![:"'])\s*//[^\n]*}{}g;

  my ($object_src) = $body
    =~ /(?:export\s+default|module\.exports\s*=)\s*(\{.*\})\s*;?\s*$/s;
  die "VueI18nJs: could not find 'export default { ... }' or 'module.exports = { ... }'\n"
    unless defined $object_src;

  my $pos  = 0;
  my $tree = _parse_object($object_src, \$pos);
  _skip_ws($object_src, \$pos);
  die "VueI18nJs: trailing content after object\n"
    unless $pos >= length $object_src;

  return $self->flatten_node($tree, '');
}

sub serialize ($self, $hash) {
  die "VueI18nJs: expected a hashref\n" unless ref $hash eq 'HASH';
  my $tree = $self->nest_flat($hash);
  my $js   = _render_value($tree, 0);
  return "export default $js;\n";
}

sub _parse_object ($src, $pos_ref) {
  _skip_ws($src, $pos_ref);
  die "VueI18nJs: expected '{' at position $$pos_ref\n"
    unless substr($src, $$pos_ref, 1) eq '{';
  $$pos_ref++;

  my %out;
  while (1) {
    _skip_ws($src, $pos_ref);
    if (substr($src, $$pos_ref, 1) eq '}') {
      $$pos_ref++;
      last;
    }

    my $key = _parse_key($src, $pos_ref);

    _skip_ws($src, $pos_ref);
    die "VueI18nJs: expected ':' after key '$key'\n"
      unless substr($src, $$pos_ref, 1) eq ':';
    $$pos_ref++;

    _skip_ws($src, $pos_ref);
    my $ch = substr($src, $$pos_ref, 1);
    my $value;
    if    ($ch eq '{') { $value = _parse_object($src, $pos_ref) }
    elsif ($ch eq '[') { $value = _parse_array($src, $pos_ref) }
    elsif ($ch eq "'" || $ch eq '"') { $value = _parse_string($src, $pos_ref, $ch) }
    else { die "VueI18nJs: unsupported value at position $$pos_ref\n" }

    $out{$key} = $value;

    _skip_ws($src, $pos_ref);
    if (substr($src, $$pos_ref, 1) eq ',') {
      $$pos_ref++;
      next;
    }
    if (substr($src, $$pos_ref, 1) eq '}') {
      $$pos_ref++;
      last;
    }
    die "VueI18nJs: expected ',' or '}' at position $$pos_ref\n";
  }

  return \%out;
}

sub _parse_array ($src, $pos_ref) {
  _skip_ws($src, $pos_ref);
  die "VueI18nJs: expected '[' at position $$pos_ref\n"
    unless substr($src, $$pos_ref, 1) eq '[';
  $$pos_ref++;

  my @out;
  while (1) {
    _skip_ws($src, $pos_ref);
    if (substr($src, $$pos_ref, 1) eq ']') {
      $$pos_ref++;
      last;
    }

    my $ch = substr($src, $$pos_ref, 1);
    my $value;
    if    ($ch eq '{') { $value = _parse_object($src, $pos_ref) }
    elsif ($ch eq '[') { $value = _parse_array($src, $pos_ref) }
    elsif ($ch eq "'" || $ch eq '"') { $value = _parse_string($src, $pos_ref, $ch) }
    else { die "VueI18nJs: unsupported array value at position $$pos_ref\n" }
    push @out, $value;

    _skip_ws($src, $pos_ref);
    if (substr($src, $$pos_ref, 1) eq ',') {
      $$pos_ref++;
      next;
    }
    if (substr($src, $$pos_ref, 1) eq ']') {
      $$pos_ref++;
      last;
    }
    die "VueI18nJs: expected ',' or ']' at position $$pos_ref\n";
  }

  return \@out;
}

sub _parse_key ($src, $pos_ref) {
  _skip_ws($src, $pos_ref);
  my $ch = substr($src, $$pos_ref, 1);
  if ($ch eq "'" || $ch eq '"') {
    return _parse_string($src, $pos_ref, $ch);
  }
  my ($key) = substr($src, $$pos_ref) =~ /\A([A-Za-z_\$][A-Za-z0-9_\$]*)/;
  die "VueI18nJs: expected identifier at position $$pos_ref\n"
    unless defined $key;
  $$pos_ref += length $key;
  return $key;
}

sub _parse_string ($src, $pos_ref, $quote) {
  die "VueI18nJs: expected quote at position $$pos_ref\n"
    unless substr($src, $$pos_ref, 1) eq $quote;
  $$pos_ref++;
  my $out = '';
  while ($$pos_ref < length $src) {
    my $ch = substr($src, $$pos_ref, 1);
    if ($ch eq '\\') {
      my $esc = substr($src, $$pos_ref + 1, 1);
      if    ($esc eq '\\') { $out .= '\\'; $$pos_ref += 2 }
      elsif ($esc eq "'")  { $out .= "'";  $$pos_ref += 2 }
      elsif ($esc eq '"')  { $out .= '"';  $$pos_ref += 2 }
      elsif ($esc eq 'n')  { $out .= "\n"; $$pos_ref += 2 }
      elsif ($esc eq 't')  { $out .= "\t"; $$pos_ref += 2 }
      elsif ($esc eq 'r')  { $out .= "\r"; $$pos_ref += 2 }
      else                 { $out .= $esc; $$pos_ref += 2 }
      next;
    }
    if ($ch eq $quote) {
      $$pos_ref++;
      return $out;
    }
    $out .= $ch;
    $$pos_ref++;
  }
  die "VueI18nJs: unterminated string\n";
}

sub _skip_ws ($src, $pos_ref) {
  while ($$pos_ref < length $src
         && substr($src, $$pos_ref, 1) =~ /\s/) {
    $$pos_ref++;
  }
}

sub _render_value ($node, $depth) {
  my $indent = '  ' x $depth;
  my $next   = '  ' x ($depth + 1);

  if (ref $node eq 'HASH') {
    return '{}' unless keys %$node;
    my @lines;
    for my $k (sort keys %$node) {
      my $kj = _js_key($k);
      my $vj = _render_value($node->{$k}, $depth + 1);
      push @lines, "$next$kj: $vj";
    }
    return "{\n" . join(",\n", @lines) . "\n$indent}";
  }

  if (ref $node eq 'ARRAY') {
    return '[]' unless @$node;
    my @lines = map { $next . _render_value($_, $depth + 1) } @$node;
    return "[\n" . join(",\n", @lines) . "\n$indent]";
  }

  return _js_string($node);
}

sub _js_key ($k) {
  return $k if $k =~ /\A[A-Za-z_\$][A-Za-z0-9_\$]*\z/;
  return _js_string($k);
}

sub _js_string ($s) {
  $s = '' unless defined $s;
  $s =~ s/\\/\\\\/g;
  $s =~ s/'/\\'/g;
  $s =~ s/\n/\\n/g;
  $s =~ s/\t/\\t/g;
  $s =~ s/\r/\\r/g;
  return "'$s'";
}

1;
