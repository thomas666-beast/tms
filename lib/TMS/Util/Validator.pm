package TMS::Util::Validator;
use strict;
use warnings;

# Matches: {name}, {{name}}, %s, %d, :name, <b>, </b>, <br />
my $TAG_RE = qr/(\{\{?\s*[A-Za-z0-9_.]+\s*\}?\}|%(?:\d+\$)?[sd]|:[A-Za-z_][A-Za-z0-9_]*|<\/?[A-Za-z][^>]*>)/;

sub extract_tags {
  my ($text) = @_;
  return [] unless defined $text;
  my @tags = ($text =~ /($TAG_RE)/g);
  return \@tags;
}

sub missing_tags {
  my ($source, $target) = @_;
  my $source_tags = extract_tags($source);
  my $target_tags = extract_tags($target);
  
  my %target_count;
  $target_count{$_}++ for @$target_tags;
  
  my @missing;
  for my $tag (@$source_tags) {
    if ($target_count{$tag} && $target_count{$tag} > 0) {
      $target_count{$tag}--;
    } else {
      push @missing, $tag;
    }
  }
  
  return \@missing;
}

1;
