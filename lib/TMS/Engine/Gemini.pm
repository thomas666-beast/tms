package TMS::Engine::Gemini;
use Mojo::Base -base, -signatures;
use Role::Tiny;

with 'TMS::Engine::Role';

use Mojo::UserAgent;

has 'api_key';
has 'ua';
has 'model' => 'gemini-1.5-flash';

sub name { 'gemini' }

sub translate ($self, $text, $from, $to) {
  die "Gemini: text is required\n"
    unless defined $text && length $text;
  die "Gemini: api_key is not configured\n"
    unless defined $self->api_key && length $self->api_key;

  my $prompt =
      "Translate the following text from $from to $to. "
    . "Return only the translation, no quotes, no explanation. "
    . "Preserve every placeholder token exactly as it appears "
    . "(:name, {name}, {{name}}, %s, %d, %1\$s).\n\n"
    . $text;

  my $ua  = $self->ua // Mojo::UserAgent->new;
  my $url = 'https://generativelanguage.googleapis.com/v1beta/models/'
          . $self->model . ':generateContent?key=' . $self->api_key;

  my $res = $ua->post($url => json => {
    contents => [
      { parts => [ { text => $prompt } ] },
    ],
  })->res;

  die "Gemini: HTTP " . $res->code . ": " . ($res->body // '') . "\n"
    unless $res->is_success;

  my $json = $res->json
    or die "Gemini: invalid JSON response\n";

  my $candidates = $json->{candidates}
    or die "Gemini: no candidates in response\n";

  my $parts = $candidates->[0]{content}{parts}
    or die "Gemini: no content parts in response\n";

  my $out = join '', map { $_->{text} // '' } @$parts;
  die "Gemini: empty translation\n" unless length $out;

  $out =~ s/^\s+|\s+$//g;
  return $out;
}

1;
