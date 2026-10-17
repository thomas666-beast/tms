use Mojo::Base -strict;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use TMS::Adapter;

my $a = TMS::Adapter->for('vue');

# --- parse: nested
{
  my $src = '{
    "welcome": "Welcome",
    "auth": {
      "login": "Sign in",
      "logout": "Sign out"
    }
  }';
  my $h = $a->parse($src);
  is $h->{welcome},       'Welcome', 'welcome';
  is $h->{'auth.login'},  'Sign in', 'auth.login';
  is $h->{'auth.logout'}, 'Sign out','auth.logout';
}

# --- parse: arrays
{
  my $src = '{"items": ["one", "two", "three"]}';
  my $h = $a->parse($src);
  is $h->{'items.0'}, 'one',   'items.0';
  is $h->{'items.1'}, 'two',   'items.1';
  is $h->{'items.2'}, 'three', 'items.2';
}

# --- parse: throws on bad JSON
{
  eval { $a->parse('{ not json') };
  like $@, qr/VueI18n:/, 'invalid JSON rejected';
}

# --- parse: throws on non-object top level
{
  eval { $a->parse('[1,2,3]') };
  like $@, qr/VueI18n: expected a JSON object/, 'top-level array rejected';
}

# --- serialize: round-trip
{
  my $hash = {
    'a'        => 'A',
    'b.c'      => 'C',
    'list.0'   => 'x',
    'list.1'   => 'y',
  };
  my $out  = $a->serialize($hash);
  my $back = $a->parse($out);
  is_deeply $back, $hash, 'round-trip equal';
}

# --- serialize: stable output (sorted keys)
{
  my $hash = { 'z' => '1', 'a' => '2', 'm' => '3' };
  my $out1 = $a->serialize($hash);
  my $out2 = $a->serialize($hash);
  is $out1, $out2, 'deterministic output';
  like $out1, qr/"a":\s*"2".*"m":\s*"3".*"z":\s*"1"/s, 'keys sorted';
}

done_testing;
