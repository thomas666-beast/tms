use Mojo::Base -strict, -signatures;
use Test::More;
use Mojo::Message::Response;

use FindBin;
use lib "$FindBin::Bin/../lib";
use TMS::Engine::Gemini;

# A fake UA that returns whatever response we hand it.
{
  package FakeUA;
  sub new ($class, $status, $body) {
    return bless { status => $status, body => $body }, $class;
  }
  sub post ($self, $url, %args) {
    my $res = Mojo::Message::Response->new;
    $res->code($self->{status});
    $res->headers->content_type('application/json');
    $res->body($self->{body});
    return Mojo::Transaction::HTTP->new->res($res);
  }
}

sub _mock_ua ($json) {
  return FakeUA->new(200, $json);
}

# ------------------------------------------------------------
# success
# ------------------------------------------------------------
{
  my $ua = _mock_ua(
    '{"candidates":[{"content":{"parts":[{"text":"Bonjour le monde"}]}}]}'
  );

  my $engine = TMS::Engine::Gemini->new(api_key => 'fake-key', ua => $ua);
  is $engine->translate('Hello world', 'en', 'fr'),
     'Bonjour le monde', 'returns candidate text';
  is $engine->name, 'gemini', 'name is gemini';
}

# ------------------------------------------------------------
# multiple parts concatenated
# ------------------------------------------------------------
{
  my $ua = _mock_ua(
    '{"candidates":[{"content":{"parts":[{"text":"Bonjour "},{"text":"le monde"}]}}]}'
  );
  my $engine = TMS::Engine::Gemini->new(api_key => 'k', ua => $ua);
  is $engine->translate('Hello world', 'en', 'fr'),
     'Bonjour le monde', 'parts concatenated';
}

# ------------------------------------------------------------
# whitespace trimmed
# ------------------------------------------------------------
{
  my $ua = _mock_ua(
    '{"candidates":[{"content":{"parts":[{"text":"  Salut  \n"}]}}]}'
  );
  my $engine = TMS::Engine::Gemini->new(api_key => 'k', ua => $ua);
  is $engine->translate('Hi', 'en', 'fr'), 'Salut', 'trimmed';
}

# ------------------------------------------------------------
# missing api_key
# ------------------------------------------------------------
{
  my $engine = TMS::Engine::Gemini->new;
  eval { $engine->translate('Hi', 'en', 'fr') };
  like $@, qr/api_key is not configured/, 'missing key rejected';
}

# ------------------------------------------------------------
# missing text
# ------------------------------------------------------------
{
  my $engine = TMS::Engine::Gemini->new(api_key => 'k');
  eval { $engine->translate('', 'en', 'fr') };
  like $@, qr/text is required/, 'empty text rejected';
}

# ------------------------------------------------------------
# no candidates
# ------------------------------------------------------------
{
  my $ua = _mock_ua('{}');
  my $engine = TMS::Engine::Gemini->new(api_key => 'k', ua => $ua);
  eval { $engine->translate('Hi', 'en', 'fr') };
  like $@, qr/no candidates/, 'no candidates rejected';
}

# ------------------------------------------------------------
# HTTP error
# ------------------------------------------------------------
{
  my $ua = FakeUA->new(500, '{"error":{"message":"boom"}}');
  my $engine = TMS::Engine::Gemini->new(api_key => 'k', ua => $ua);
  eval { $engine->translate('Hi', 'en', 'fr') };
  like $@, qr/Gemini: HTTP 500/, 'HTTP error surfaces';
}

done_testing;
