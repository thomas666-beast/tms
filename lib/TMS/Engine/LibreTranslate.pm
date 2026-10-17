package TMS::Engine::LibreTranslate;
use Mojo::Base -base, -signatures;
use Role::Tiny;

with 'TMS::Engine::Role';

use Mojo::UserAgent;

has 'url';
has 'ua';

sub name { 'libretranslate' }

sub translate ($self, $text, $from, $to) {
  die "LibreTranslate: text is required\n"
    unless defined $text && length $text;
  die "LibreTranslate: url is not configured\n"
    unless defined $self->url && length $self->url;

  my $ua  = $self->ua // Mojo::UserAgent->new;
  my $res = $ua->post(
    $self->url . '/translate' => json => {
      q      => $text,
      source => $from,
      target => $to,
      format => 'text',
    },
  )->res;

  die "LibreTranslate: HTTP " . $res->code . ": " . ($res->body // '') . "\n"
    unless $res->is_success;

  my $json = $res->json
    or die "LibreTranslate: invalid JSON response\n";

  die "LibreTranslate: " . ($json->{error} // 'unknown error') . "\n"
    if $json->{error};

  my $out = $json->{translatedText};
  die "LibreTranslate: empty response\n"
    unless defined $out;

  return $out;
}

1;
