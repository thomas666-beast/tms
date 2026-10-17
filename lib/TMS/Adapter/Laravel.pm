package TMS::Adapter::Laravel;
use Mojo::Base -base, -signatures;
use Role::Tiny;

with 'TMS::Adapter::Role';

sub name      { 'laravel' }
sub extension { 'php' }

sub parse ($self, $content) {
  die "Laravel: content is not a string\n" unless defined $content;

  my $body = $content;
  $body =~ s/^\x{FEFF}//;

  my ($array_src) = $body =~ /\breturn\s*(\[.*\])\s*;/s;
  die "Laravel: could not find 'return [ ... ];' in file\n"
    unless defined $array_src;

  my $pos  = 0;
  my $tree = _parse_array($array_src, \$pos);
  _skip_ws($array_src, \$pos);
  die "Laravel: trailing content after return array\n"
    unless $pos >= length $array_src;

  return _flatten($tree, '');
}

sub serialize ($self, $hash) {
  die "Laravel: expected a hashref\n" unless ref $hash eq 'HASH';

  my $tree = _nest($hash);
  my $php  = _render_array($tree, 0);
  return "<?php\n\nreturn $php;\n";
}

sub _parse_array ($src, $pos_ref) {
  _skip_ws($src, $pos_ref);
  die "Laravel: expected '[' at position $$pos_ref\n"
    unless substr($src, $$pos_ref, 1) eq '[';

  $$pos_ref++;

  my @items;
  while (1) {
    _skip_ws($src, $pos_ref);

    if (substr($src, $$pos_ref, 1) eq ']') {
      $$pos_ref++;
      last;
    }

    my $next = substr($src, $$pos_ref, 1);
    my $item;
    if ($next eq '[') {
      $item = _parse_array($src, $pos_ref);
    }
    elsif ($next eq "'" || $next eq '"') {
      $item = _parse_string($src, $pos_ref, $next);
    }
    else {
      die "Laravel: unsupported token at position $$pos_ref\n";
    }

    _skip_ws($src, $pos_ref);

    if (substr($src, $$pos_ref, 2) eq '=>') {
      $$pos_ref += 2;
      _skip_ws($src, $pos_ref);

      my $vn    = substr($src, $$pos_ref, 1);
      my $value;
      if ($vn eq '[') {
        $value = _parse_array($src, $pos_ref);
      }
      elsif ($vn eq "'" || $vn eq '"') {
        $value = _parse_string($src, $pos_ref, $vn);
      }
      else {
        die "Laravel: unsupported value token at position $$pos_ref\n";
      }

      push @items, [ $item, $value ];
    }
    else {
      push @items, [ undef, $item ];
    }

    _skip_ws($src, $pos_ref);
    if (substr($src, $$pos_ref, 1) eq ',') {
      $$pos_ref++;
      next;
    }
    if (substr($src, $$pos_ref, 1) eq ']') {
      $$pos_ref++;
      last;
    }
    die "Laravel: expected ',' or ']' at position $$pos_ref\n";
  }

  my $has_keys = grep { defined $_->[0] } @items;

  if ($has_keys) {
    my %out;
    for my $pair (@items) {
      my ($k, $v) = @$pair;
      die "Laravel: mixed associative and bare entries\n" unless defined $k;
      $out{$k} = $v;
    }
    return \%out;
  }

  return [ map { $_->[1] } @items ];
}

sub _parse_string ($src, $pos_ref, $quote) {
  die "Laravel: expected quote at position $$pos_ref\n"
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

  die "Laravel: unterminated string\n";
}

sub _skip_ws ($src, $pos_ref) {
  while ($$pos_ref < length $src && substr($src, $$pos_ref, 1) =~ /\s/) {
    $$pos_ref++;
  }
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

sub _render_array ($node, $depth) {
  my $indent      = '    ' x $depth;
  my $next_indent = '    ' x ($depth + 1);

  if (ref $node eq 'ARRAY') {
    return '[]' unless @$node;
    my @lines = map { $next_indent . _render_value($_, $depth + 1) . ',' } @$node;
    return "[\n" . join("\n", @lines) . "\n$indent]";
  }

  return '[]' unless keys %$node;
  my @lines;
  for my $k (sort keys %$node) {
    my $key_php = _php_string($k);
    my $val_php = _render_value($node->{$k}, $depth + 1);
    push @lines, "$next_indent$key_php => $val_php,";
  }
  return "[\n" . join("\n", @lines) . "\n$indent]";
}

sub _render_value ($node, $depth) {
  return _render_array($node, $depth) if ref $node;
  return _php_string($node);
}

sub _php_string ($s) {
  $s = '' unless defined $s;
  $s =~ s/\\/\\\\/g;
  $s =~ s/'/\\'/g;
  $s =~ s/\n/\\n/g;
  $s =~ s/\t/\\t/g;
  $s =~ s/\r/\\r/g;
  return "'$s'";
}

1;
