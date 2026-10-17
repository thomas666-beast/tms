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

# ------------------------------------------------------------
# login
# ------------------------------------------------------------
$t->post_ok('/api/v1/auth/login' => json => {
  email    => $admin_email,
  password => $admin_password,
})
  ->status_is(200)
  ->json_has('/csrf_token');

my $csrf = $t->tx->res->json->{csrf_token};
my %h    = ('X-CSRF-Token' => $csrf);

my $db = $t->app->pg_pool->db;

# ------------------------------------------------------------
# cleanup + setup
# ------------------------------------------------------------
$db->query(q{DELETE FROM users WHERE email LIKE 'test-files-%@example.com'});
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-files-%'});

$t->post_ok('/api/v1/projects' => {%h} => json => {
  name                => 'Test Files Project',
  default_source_lang => 'en',
})
  ->status_is(201);
my $project_id = $t->tx->res->json->{project}{id};

# ------------------------------------------------------------
# upload: validation
# ------------------------------------------------------------
$t->post_ok("/api/v1/projects/$project_id/files" => {%h} => form => {})
  ->status_is(400)
  ->json_is('/error', 'format_required');

$t->post_ok("/api/v1/projects/$project_id/files" => {%h} => form => {
  format      => 'laravel',
  source_lang => 'en',
})
  ->status_is(400)
  ->json_is('/error', 'target_lang_required');

$t->post_ok("/api/v1/projects/$project_id/files" => {%h} => form => {
  format      => 'wizard',
  source_lang => 'en',
  target_lang => 'fr',
})
  ->status_is(400)
  ->json_is('/error', 'unsupported_format');

$t->post_ok("/api/v1/projects/$project_id/files" => {%h} => form => {
  format      => 'laravel',
  source_lang => 'en',
  target_lang => 'fr',
})
  ->status_is(400)
  ->json_is('/error', 'file_required');

# ------------------------------------------------------------
# upload: valid Laravel file
# ------------------------------------------------------------
my $laravel_content = <<'PHP';
<?php

return [
    'welcome' => 'Welcome',
    'auth' => [
        'login'  => 'Sign in',
        'logout' => 'Sign out',
    ],
];
PHP

$t->post_ok("/api/v1/projects/$project_id/files" => {%h} => form => {
  format      => 'laravel',
  source_lang => 'en',
  target_lang => 'fr',
  name        => 'auth.php',
  file        => { content => $laravel_content, filename => 'auth.php' },
})
  ->status_is(201)
  ->json_is('/file/name',        'auth.php')
  ->json_is('/file/format',      'laravel')
  ->json_is('/file/source_lang', 'en')
  ->json_is('/file/target_lang', 'fr')
  ->json_is('/file/status',      'in_progress')
  ->json_is('/file/keys_count',  3);

my $file_id = $t->tx->res->json->{file}{id};

# keys should exist
my $keys = $db->query(
  'SELECT key_path, source_text FROM keys WHERE file_id = ? ORDER BY key_path',
  $file_id,
)->hashes;
is scalar(@$keys), 3, 'three keys stored';
is $keys->[0]{key_path},    'auth.login',  'first key path';
is $keys->[0]{source_text}, 'Sign in',     'first key value';

# revision created and linked
my $file_row = $db->query(
  'SELECT status, current_revision_id FROM files WHERE id = ?',
  $file_id,
)->hash;
ok defined $file_row->{current_revision_id}, 'current_revision_id set';

my $revision = $db->query(
  'SELECT revision_number, status FROM file_revisions WHERE id = ?',
  $file_row->{current_revision_id},
)->hash;
is $revision->{revision_number}, 1,       'revision number is 1';
is $revision->{status},          'open',  'revision status is open';

# ------------------------------------------------------------
# duplicate: 409
# ------------------------------------------------------------
$t->post_ok("/api/v1/projects/$project_id/files" => {%h} => form => {
  format      => 'laravel',
  source_lang => 'en',
  target_lang => 'fr',
  name        => 'auth.php',
  file        => { content => $laravel_content, filename => 'auth.php' },
})
  ->status_is(409)
  ->json_is('/error', 'file_exists');

# ------------------------------------------------------------
# upload: invalid file (bad PHP)
# ------------------------------------------------------------
$t->post_ok("/api/v1/projects/$project_id/files" => {%h} => form => {
  format      => 'laravel',
  source_lang => 'en',
  target_lang => 'ar',
  name        => 'broken.php',
  file        => { content => 'not php at all', filename => 'broken.php' },
})
  ->status_is(400)
  ->json_is('/error', 'invalid_file');

# ------------------------------------------------------------
# upload: valid Vue-i18n file
# ------------------------------------------------------------
my $vue_content = '{"welcome":"Welcome","auth":{"login":"Sign in","logout":"Sign out"}}';

$t->post_ok("/api/v1/projects/$project_id/files" => {%h} => form => {
  format      => 'vue',
  source_lang => 'en',
  target_lang => 'fr',
  name        => 'ui.json',
  file        => { content => $vue_content, filename => 'ui.json' },
})
  ->status_is(201)
  ->json_is('/file/format', 'vue')
  ->json_is('/file/keys_count', 3);

# ------------------------------------------------------------
# non-admin cannot upload
# ------------------------------------------------------------
$t->post_ok('/api/v1/users' => {%h} => json => {
  email    => 'test-files-translator@example.com',
  name     => 'Files Translator',
  password => 'password-1',
  role     => 'translator',
})
  ->status_is(201);
my $translator_id = $t->tx->res->json->{user}{id};

$t->post_ok("/api/v1/projects/$project_id/members" => {%h} => json => {
  user_id => $translator_id, role => 'translator',
})
  ->status_is(201);

$t->post_ok('/api/v1/auth/logout' => {%h})
  ->status_is(200);

$t->post_ok('/api/v1/auth/login' => json => {
  email    => 'test-files-translator@example.com',
  password => 'password-1',
})
  ->status_is(200);
my $tcsrf = $t->tx->res->json->{csrf_token};
my %th    = ('X-CSRF-Token' => $tcsrf);

$t->post_ok("/api/v1/projects/$project_id/files" => {%th} => form => {
  format      => 'laravel',
  source_lang => 'en',
  target_lang => 'de',
  name        => 'auth.php',
  file        => { content => $laravel_content, filename => 'auth.php' },
})
  ->status_is(403)
  ->json_is('/error', 'forbidden');

# ------------------------------------------------------------
# cleanup
# ------------------------------------------------------------
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-files-%'});
$db->query(q{DELETE FROM users    WHERE email LIKE 'test-files-%@example.com'});

done_testing;
