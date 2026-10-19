use Mojo::Base -strict, -signatures;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use TMS::Adapter;

my $a = TMS::Adapter->for('vue_js');
is $a->name, 'vue_js', 'name';
is $a->extension, 'js', 'extension';

# export default
{
  my $src = <<'JS';
export default {
  welcome: 'Welcome',
  auth: {
    login: 'Sign in',
    logout: 'Sign out'
  },
  items: ['one', 'two']
};
JS
  my $h = $a->parse($src);
  is $h->{welcome},       'Welcome',  'welcome';
  is $h->{'auth.login'},  'Sign in',  'auth.login';
  is $h->{'auth.logout'}, 'Sign out', 'auth.logout';
  is $h->{'items.0'},     'one',      'items.0';
  is $h->{'items.1'},     'two',      'items.1';
}

# module.exports with double quotes and trailing semicolon
{
  my $src = q{module.exports = { "hello": "Hello", "plural": "no items | one item | {count} items" };};
  my $h = $a->parse($src);
  is $h->{hello},  'Hello', 'hello';
  is $h->{plural}, 'no items | one item | {count} items', 'pipe plurals kept as string';
}

# round-trip
{
  my $hash = { 'a' => 'A', 'b.c' => 'C', 'list.0' => 'x' };
  my $out  = $a->serialize($hash);
  like $out, qr/^export default \{/, 'output is export default';
  my $back = $a->parse($out);
  is_deeply $back, $hash, 'round-trip equal';
}

# rejects unsupported content
{
  eval { $a->parse("const x = 1;") };
  like $@, qr/VueI18nJs:/, 'rejects non-export content';
}

# still JSON-only
{
  eval { TMS::Adapter->for('vue')->parse("export default {}") };
  like $@, qr/VueI18n:/, 'json adapter rejects JS';
}

done_testing;
