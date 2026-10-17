use Mojo::Base -strict, -signatures;
use Test::More;
use Test::Mojo;
use Mojo::JSON qw(decode_json);

use FindBin;
use lib "$FindBin::Bin/../lib";
require "$FindBin::Bin/testlib.pl";
use TMS;

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
$db->query(q{DELETE FROM users WHERE email LIKE 'test-exp-%@example.com'});
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-exp-%'});

$t->post_ok('/api/v1/auth/login' => json => {
  email    => $admin_email,
  password => $admin_password,
})
  ->status_is(200)
  ->json_has('/csrf_token');
my $csrf = $t->tx->res->json->{csrf_token};
my %h    = ('X-CSRF-Token' => $csrf);

$t->post_ok('/api/v1/projects' => {%h} => json => {
  name                => 'Export Project',
  default_source_lang => 'en',
})
  ->status_is(201);
my $project_id = $t->tx->res->json->{project}{id};

# ------------------------------------------------------------
# Laravel file: some translated, some not
# ------------------------------------------------------------
my $laravel = <<'PHP';
<?php

return [
    'welcome' => 'Welcome',
    'goodbye' => 'Goodbye',
    'hello'   => 'Hello :name',
];
PHP

$t->post_ok("/api/v1/projects/$project_id/files" => {%h} => form => {
  format      => 'laravel',
  source_lang => 'en',
  target_lang => 'fr',
  name        => 'strings.php',
  file        => { content => $laravel, filename => 'strings.php' },
})
  ->status_is(201);
my $file_id = $t->tx->res->json->{file}{id};

$t->get_ok("/api/v1/files/$file_id/keys")
  ->status_is(200);
my $keys = $t->tx->res->json->{keys};
my ($welcome) = grep { $_->{key_path} eq 'welcome' } @$keys;

# translate one key
$t->patch_ok("/api/v1/keys/$welcome->{id}/translation" => {%h} => json => {
  text => 'Bienvenue',
})
  ->status_is(200);

# ------------------------------------------------------------
# export current: welcome translated, others fall back to source
# ------------------------------------------------------------
$t->get_ok("/api/v1/files/$file_id/export")
  ->status_is(200);

my $ct = $t->tx->res->headers->content_type;
like $ct, qr{text/x-php}, 'content-type php';

my $cd = $t->tx->res->headers->content_disposition;
like $cd, qr{attachment; filename="strings\.php"}, 'attachment filename';

my $body = $t->tx->res->body;
like $body, qr/^<\?php/, 'starts with php tag';
like $body, qr/'welcome' => 'Bienvenue'/, 'translated value present';
like $body, qr/'goodbye' => 'Goodbye'/,  'untranslated falls back to source';
like $body, qr/'hello' => 'Hello :name'/, 'placeholder key falls back';

# ------------------------------------------------------------
# Vue file export
# ------------------------------------------------------------
my $vue = '{"a":"Apple","b":"Banana"}';

$t->post_ok("/api/v1/projects/$project_id/files" => {%h} => form => {
  format      => 'vue',
  source_lang => 'en',
  target_lang => 'de',
  name        => 'ui.json',
  file        => { content => $vue, filename => 'ui.json' },
})
  ->status_is(201);
my $vue_id = $t->tx->res->json->{file}{id};

$t->get_ok("/api/v1/files/$vue_id/export")
  ->status_is(200);
like $t->tx->res->headers->content_type, qr{application/json}, 'content-type json';
like $t->tx->res->headers->content_disposition, qr{filename="ui\.json"}, 'vue filename';

my $vue_body = $t->tx->res->body;
my $parsed = eval { decode_json($vue_body) };
ok $parsed, 'exports valid JSON';
is $parsed->{a}, 'Apple', 'source fallback a';
is $parsed->{b}, 'Banana', 'source fallback b';

# ------------------------------------------------------------
# latest_approved: no approved revision yet -> 404
# ------------------------------------------------------------
$t->get_ok("/api/v1/files/$file_id/export?revision=latest_approved")
  ->status_is(404)
  ->json_is('/error', 'no_approved_revision');

# ------------------------------------------------------------
# invalid revision param
# ------------------------------------------------------------
$t->get_ok("/api/v1/files/$file_id/export?revision=wizard")
  ->status_is(400)
  ->json_is('/error', 'invalid_revision');

# ------------------------------------------------------------
# non-member cannot export
# ------------------------------------------------------------
$t->post_ok('/api/v1/users' => {%h} => json => {
  email    => 'test-exp-out@example.com',
  name     => 'Out',
  password => 'password-1',
  role     => 'translator',
})
  ->status_is(201);

$t->post_ok('/api/v1/auth/logout' => {%h})
  ->status_is(200);
$t->post_ok('/api/v1/auth/login' => json => {
  email    => 'test-exp-out@example.com',
  password => 'password-1',
})
  ->status_is(200);

$t->get_ok("/api/v1/files/$file_id/export")
  ->status_is(403);

# ------------------------------------------------------------
# cleanup
# ------------------------------------------------------------
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-exp-%'});
$db->query(q{DELETE FROM users    WHERE email LIKE 'test-exp-%@example.com'});

done_testing;
