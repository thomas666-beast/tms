use Mojo::Base -strict;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use TMS::Adapter;

my $a = TMS::Adapter->for('laravel');

# --- parse: simple
{
  my $src = q{<?php

return [
    'welcome' => 'Welcome',
    'goodbye' => 'Goodbye',
];
};
  my $h = $a->parse($src);
  is $h->{welcome}, 'Welcome', 'welcome parsed';
  is $h->{goodbye}, 'Goodbye', 'goodbye parsed';
}

# --- parse: nested
{
  my $src = q{<?php return [
    'auth' => [
        'login'  => 'Sign in',
        'logout' => 'Sign out',
    ],
];};
  my $h = $a->parse($src);
  is $h->{'auth.login'},  'Sign in',  'auth.login';
  is $h->{'auth.logout'}, 'Sign out', 'auth.logout';
}

# --- parse: array values
{
  my $src = q{<?php return [
    'items' => ['one', 'two', 'three'],
];};
  my $h = $a->parse($src);
  is $h->{'items.0'}, 'one',   'items.0';
  is $h->{'items.1'}, 'two',   'items.1';
  is $h->{'items.2'}, 'three', 'items.2';
}

# --- parse: escapes
{
  my $src = q{<?php return [
    'line' => 'line1\nline2',
    'quote' => 'it\'s ok',
];};
  my $h = $a->parse($src);
  is $h->{line},  "line1\nline2", 'escape \\n';
  is $h->{quote}, "it's ok",      'escape \\\'';
}

# --- parse: throws on invalid
{
  eval { $a->parse('<?php echo 1;') };
  like $@, qr/Laravel:/, 'invalid input rejected';
}

# --- serialize: round-trip
{
  my $src = q{<?php return [
    'a' => 'A',
    'b' => [
        'c' => 'C',
    ],
];};
  my $h  = $a->parse($src);
  my $out = $a->serialize($h);
  like $out, qr/^<\?php\n\nreturn \[/, 'output starts with php tag';
  like $out, qr/'a' => 'A'/, 'output has a';
  like $out, qr/'c' => 'C'/, 'output has nested c';

  my $h2 = $a->parse($out);
  is_deeply $h2, $h, 'round-trip equal';
}

done_testing;
