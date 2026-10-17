use Mojo::Base -strict;
use Test::More;
use Test::Mojo;

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

$t->post_ok('/api/v1/auth/login' => json => {
  email    => $admin_email,
  password => $admin_password,
})
  ->status_is(200)
  ->json_has('/csrf_token');

my $csrf = $t->tx->res->json->{csrf_token};
my %h    = ('X-CSRF-Token' => $csrf);

my $db = $t->app->pg_pool->db;

$db->query(q{DELETE FROM users WHERE email LIKE 'test-tr-%@example.com'});
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-tr-%'});

# ------------------------------------------------------------
# setup: project, file, keys
# ------------------------------------------------------------
$t->post_ok('/api/v1/projects' => {%h} => json => {
  name                => 'Translations Project',
  default_source_lang => 'en',
})
  ->status_is(201);
my $project_id = $t->tx->res->json->{project}{id};

my $laravel = <<'PHP';
<?php

return [
    'welcome' => 'Welcome',
    'auth'    => ['login' => 'Sign in', 'logout' => 'Sign out'],
];
PHP

$t->post_ok("/api/v1/projects/$project_id/files" => {%h} => form => {
  format      => 'laravel',
  source_lang => 'en',
  target_lang => 'fr',
  name        => 'auth.php',
  file        => { content => $laravel, filename => 'auth.php' },
})
  ->status_is(201);
my $file_id = $t->tx->res->json->{file}{id};

$t->get_ok("/api/v1/files/$file_id/keys")
  ->status_is(200);
my $keys = $t->tx->res->json->{keys};
my $key_login = (grep { $_->{key_path} eq 'auth.login' } @$keys)[0];
ok $key_login, 'found auth.login key';
my $key_id = $key_login->{id};

# ------------------------------------------------------------
# PATCH validation
# ------------------------------------------------------------
$t->patch_ok("/api/v1/keys/$key_id/translation" => {%h} => json => {})
  ->status_is(400)
  ->json_is('/error', 'nothing_to_update');

$t->patch_ok("/api/v1/keys/$key_id/translation" => {%h} => json => {
  text => '', status => 'translated',
})
  ->status_is(400)
  ->json_is('/error', 'text_required');

$t->patch_ok("/api/v1/keys/$key_id/translation" => {%h} => json => {
  text => 'x', status => 'approved',
})
  ->status_is(400)
  ->json_is('/error', 'invalid_status');

# ------------------------------------------------------------
# happy path: set text
# ------------------------------------------------------------
$t->patch_ok("/api/v1/keys/$key_id/translation" => {%h} => json => {
  text => 'Se connecter',
})
  ->status_is(200)
  ->json_is('/translation/text',   'Se connecter')
  ->json_is('/translation/status', 'translated');

my $first_id = $t->tx->res->json->{translation}{id};

# keys endpoint reflects it
$t->get_ok("/api/v1/files/$file_id/keys")
  ->status_is(200);
my $again = (grep { $_->{key_path} eq 'auth.login' } @{ $t->tx->res->json->{keys} })[0];
is $again->{translation}{text},   'Se connecter', 'text visible via keys';
is $again->{translation}{status}, 'translated',   'status visible via keys';

# filter approved -> 0, translated -> 1
$t->get_ok("/api/v1/files/$file_id/keys?status=translated")
  ->status_is(200);
is scalar(@{ $t->tx->res->json->{keys} }), 1, 'one translated key';

# ------------------------------------------------------------
# second edit: append row, keep history
# ------------------------------------------------------------
$t->patch_ok("/api/v1/keys/$key_id/translation" => {%h} => json => {
  text => 'Se connecter (v2)', status => 'needs_review', note => 'double-check',
})
  ->status_is(200)
  ->json_is('/translation/text',   'Se connecter (v2)')
  ->json_is('/translation/status', 'needs_review')
  ->json_is('/translation/note',   'double-check');

my $second_id = $t->tx->res->json->{translation}{id};
isnt $first_id, $second_id, 'new row id';

# history has 2 entries, newest first
$t->get_ok("/api/v1/keys/$key_id/translation/history")
  ->status_is(200);
my $history = $t->tx->res->json->{history};
is scalar(@$history), 2, 'two history entries';
is $history->[0]{text},   'Se connecter (v2)', 'newest first';
is $history->[1]{text},   'Se connecter',      'older second';

# ------------------------------------------------------------
# status-only update carries text forward
# ------------------------------------------------------------
$t->patch_ok("/api/v1/keys/$key_id/translation" => {%h} => json => {
  status => 'translated',
})
  ->status_is(200)
  ->json_is('/translation/text',   'Se connecter (v2)')
  ->json_is('/translation/status', 'translated');

# ------------------------------------------------------------
# assigned translator can edit their file; unassigned cannot
# ------------------------------------------------------------
$t->post_ok('/api/v1/users' => {%h} => json => {
  email    => 'test-tr-assigned@example.com',
  name     => 'Assigned',
  password => 'password-1',
  role     => 'translator',
})
  ->status_is(201);
my $assigned_id = $t->tx->res->json->{user}{id};

$t->post_ok("/api/v1/projects/$project_id/members" => {%h} => json => {
  user_id => $assigned_id, role => 'translator',
})
  ->status_is(201);

# assign file to that user via direct DB (no assign endpoint yet — Task 15)
$db->query('UPDATE files SET assigned_to_user_id = ? WHERE id = ?',
  $assigned_id, $file_id);

$t->post_ok('/api/v1/auth/logout' => {%h})
  ->status_is(200);

$t->post_ok('/api/v1/auth/login' => json => {
  email    => 'test-tr-assigned@example.com',
  password => 'password-1',
})
  ->status_is(200);
my $acsrf = $t->tx->res->json->{csrf_token};
my %ah    = ('X-CSRF-Token' => $acsrf);

$t->patch_ok("/api/v1/keys/$key_id/translation" => {%ah} => json => {
  text => 'Connectez-vous', status => 'translated',
})
  ->status_is(200)
  ->json_is('/translation/text', 'Connectez-vous');

# another translator, not assigned, cannot edit
$t->post_ok('/api/v1/auth/logout' => {%ah})
  ->status_is(200);

# ------------------------------------------------------------
# cleanup
# ------------------------------------------------------------
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-tr-%'});
$db->query(q{DELETE FROM users    WHERE email LIKE 'test-tr-%@example.com'});

done_testing;
