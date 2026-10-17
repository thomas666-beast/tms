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

$db->query(q{DELETE FROM users WHERE email LIKE 'test-reads-%@example.com'});
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-reads-%'});

# ------------------------------------------------------------
# setup: project + one file
# ------------------------------------------------------------
$t->post_ok('/api/v1/projects' => {%h} => json => {
  name                => 'Reads Project',
  default_source_lang => 'en',
})
  ->status_is(201);
my $project_id = $t->tx->res->json->{project}{id};

my $laravel = <<'PHP';
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
  file        => { content => $laravel, filename => 'auth.php' },
})
  ->status_is(201);
my $file_id = $t->tx->res->json->{file}{id};

# ------------------------------------------------------------
# GET /projects/:id/files
# ------------------------------------------------------------
$t->get_ok("/api/v1/projects/$project_id/files")
  ->status_is(200);

my $files = $t->tx->res->json->{files};
is scalar(@$files), 1, 'one file';
is $files->[0]{id},         $file_id,        'file id matches';
is $files->[0]{keys_count}, 3,               'keys_count correct';
is $files->[0]{format},     'laravel',       'format correct';
ok !defined $files->[0]{assigned_to_user_id}, 'not assigned yet';

# nonexistent project
$t->get_ok('/api/v1/projects/999999/files')
  ->status_is(404)
  ->json_is('/error', 'project_not_found');

# ------------------------------------------------------------
# GET /files/:id
# ------------------------------------------------------------
$t->get_ok("/api/v1/files/$file_id")
  ->status_is(200)
  ->json_is('/file/id', $file_id)
  ->json_is('/file/name', 'auth.php')
  ->json_is('/revision/revision_number', 1)
  ->json_is('/revision/status', 'open');

$t->get_ok('/api/v1/files/999999')
  ->status_is(404)
  ->json_is('/error', 'file_not_found');

# ------------------------------------------------------------
# GET /files/:id/keys
# ------------------------------------------------------------
$t->get_ok("/api/v1/files/$file_id/keys")
  ->status_is(200);

my $keys = $t->tx->res->json->{keys};
is scalar(@$keys), 3, 'three keys';
is $keys->[0]{key_path},    'auth.login',  'sorted by key_path';
is $keys->[0]{source_text}, 'Sign in',     'source text present';
ok !defined $keys->[0]{translation}, 'no translation yet';

# filter empty -> all 3
$t->get_ok("/api/v1/files/$file_id/keys?status=empty")
  ->status_is(200);
is scalar(@{ $t->tx->res->json->{keys} }), 3, 'empty filter shows all';

# filter approved -> 0
$t->get_ok("/api/v1/files/$file_id/keys?status=approved")
  ->status_is(200);
is scalar(@{ $t->tx->res->json->{keys} }), 0, 'approved filter shows none';

# invalid filter -> 400
$t->get_ok("/api/v1/files/$file_id/keys?status=wizard")
  ->status_is(400)
  ->json_is('/error', 'invalid_status');

# ------------------------------------------------------------
# non-member cannot see the file
# ------------------------------------------------------------
$t->post_ok('/api/v1/users' => {%h} => json => {
  email    => 'test-reads-out@example.com',
  name     => 'Outsider',
  password => 'password-1',
  role     => 'translator',
})
  ->status_is(201);

$t->post_ok('/api/v1/auth/logout' => {%h})
  ->status_is(200);

$t->post_ok('/api/v1/auth/login' => json => {
  email    => 'test-reads-out@example.com',
  password => 'password-1',
})
  ->status_is(200);

$t->get_ok("/api/v1/files/$file_id")
  ->status_is(403);

$t->get_ok("/api/v1/files/$file_id/keys")
  ->status_is(403);

# ------------------------------------------------------------
# cleanup
# ------------------------------------------------------------
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-reads-%'});
$db->query(q{DELETE FROM users    WHERE email LIKE 'test-reads-%@example.com'});

done_testing;
