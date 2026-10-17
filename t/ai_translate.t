use Mojo::Base -strict, -signatures;
use Test::More;
use Test::Mojo;

use FindBin;
use lib "$FindBin::Bin/../lib";
require "$FindBin::Bin/testlib.pl";
use TMS;
use TMS::Engine;

{
  package FakeEngine;
  sub new { my ($class, %a) = @_; bless {%a}, $class }
  sub name { $_[0]->{name} }
  sub translate {
    my ($self, $text, $from, $to) = @_;
    my $out = "X:$text";
    $out =~ s/:name//g;
    return $out;
  }
}

$TMS::Engine::FOR_TEST = sub ($name, $opts) {
  return FakeEngine->new(name => $name);
};

my $t = Test::Mojo->new('TMS');

my $admin_email    = $ENV{TMS_DEV_ADMIN_EMAIL}    // 'admin@example.com';
my $admin_password = $ENV{TMS_DEV_ADMIN_PASSWORD};

my $admin = $t->app->pg_pool->db->query(
  'SELECT id FROM users WHERE email = ? AND is_active AND role = ?',
  $admin_email, 'admin',
)->hash;

plan skip_all => 'no seeded admin (run script/test_db.pl first)'
  unless $admin && $admin_password;

my $db = $t->app->pg_pool->db;
$db->query(q{DELETE FROM users WHERE email LIKE 'test-ai-%@example.com'});
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-ai-%'});

$t->post_ok('/api/v1/auth/login' => json => {
  email    => $admin_email,
  password => $admin_password,
})
  ->status_is(200)
  ->json_has('/csrf_token');
my $csrf = $t->tx->res->json->{csrf_token};
my %h    = ('X-CSRF-Token' => $csrf);

$t->post_ok('/api/v1/projects' => {%h} => json => {
  name                => 'AI Project',
  default_source_lang => 'en',
})
  ->status_is(201);
my $project_id = $t->tx->res->json->{project}{id};

my $laravel = <<'PHP';
<?php

return [
    'welcome' => 'Welcome',
    'user'    => 'Hello :name',
];
PHP

$t->post_ok("/api/v1/projects/$project_id/files" => {%h} => form => {
  format      => 'laravel',
  source_lang => 'en',
  target_lang => 'fr',
  name        => 'ai.php',
  file        => { content => $laravel, filename => 'ai.php' },
})
  ->status_is(201);
my $file_id = $t->tx->res->json->{file}{id};

$t->get_ok("/api/v1/files/$file_id/keys")
  ->status_is(200);
my $keys = $t->tx->res->json->{keys};
my ($welcome) = grep { $_->{key_path} eq 'welcome' } @$keys;
my ($user)    = grep { $_->{key_path} eq 'user' }    @$keys;

$t->post_ok("/api/v1/keys/$welcome->{id}/ai_translate" => {%h} => json => {
  engine => 'libretranslate',
})
  ->status_is(200)
  ->json_is('/translation/status', 'ai_draft')
  ->json_is('/translation/translated_by_ai', 1)
  ->json_is('/translation/ai_engine', 'libretranslate');

is $t->tx->res->json->{translation}{text}, 'X:Welcome', 'fake engine response';

$t->post_ok("/api/v1/keys/$user->{id}/ai_translate" => {%h} => json => {
  engine => 'libretranslate',
})
  ->status_is(200)
  ->json_is('/translation/status', 'needs_review');

like $t->tx->res->json->{translation}{note} // '', qr/Placeholders missing/,
  'note mentions missing placeholders';

my $laravel2 = <<'PHP';
<?php

return [
    'a' => 'Apple',
    'b' => 'Banana',
];
PHP

$t->post_ok("/api/v1/projects/$project_id/files" => {%h} => form => {
  format      => 'laravel',
  source_lang => 'en',
  target_lang => 'de',
  name        => 'bulk.php',
  file        => { content => $laravel2, filename => 'bulk.php' },
})
  ->status_is(201);
my $bulk_id = $t->tx->res->json->{file}{id};

$t->post_ok("/api/v1/files/$bulk_id/ai_translate" => {%h} => json => {
  engine => 'libretranslate',
})
  ->status_is(200)
  ->json_is('/translated', 2)
  ->json_is('/errors',     0);

$t->post_ok("/api/v1/files/$bulk_id/ai_translate" => {%h} => json => {
  engine => 'libretranslate',
})
  ->status_is(200)
  ->json_is('/total', 0);

$t->post_ok("/api/v1/keys/$welcome->{id}/ai_translate" => {%h} => json => {
  engine => 'wizard',
})
  ->status_is(400)
  ->json_is('/error', 'unsupported_engine');

# same fake engine, but with name 'gemini', to prove the plumbing accepts both engines
$t->post_ok("/api/v1/keys/$welcome->{id}/ai_translate" => {%h} => json => {
  engine => 'gemini',
})
  ->status_is(200)
  ->json_is('/translation/status', 'ai_draft')
  ->json_is('/translation/ai_engine', 'gemini');

$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-ai-%'});
$db->query(q{DELETE FROM users    WHERE email LIKE 'test-ai-%@example.com'});

done_testing;
