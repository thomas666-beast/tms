use Mojo::Base -strict;
use Test::More;
use Test::Mojo;

use FindBin;
use lib "$FindBin::Bin/../lib";
use TMS;

my $t = Test::Mojo->new('TMS');

my $admin_email    = $ENV{TMS_DEV_ADMIN_EMAIL}    // 'admin@example.com';
my $admin_password = $ENV{TMS_DEV_ADMIN_PASSWORD};

# ------------------------------------------------------------
# guard: skip if no dev admin
# ------------------------------------------------------------
my $admin = $t->app->pg_pool->db->query(
  'SELECT id FROM users WHERE email = ? AND is_active AND role = ?',
  $admin_email, 'admin',
)->hash;

plan skip_all => 'no seeded admin (run script/reset_db.pl first)'
  unless $admin && $admin_password;

# ------------------------------------------------------------
# login as admin, capture CSRF
# ------------------------------------------------------------
$t->post_ok('/api/v1/auth/login' => json => {
  email    => $admin_email,
  password => $admin_password,
})
  ->status_is(200)
  ->json_has('/csrf_token');

my $csrf = $t->tx->res->json->{csrf_token};
ok(defined $csrf && length $csrf, 'admin csrf token present');

my %h = ('X-CSRF-Token' => $csrf);

# ------------------------------------------------------------
# cleanup: remove any test users from prior runs
# ------------------------------------------------------------
my $db = $t->app->pg_pool->db;
$db->query(q{DELETE FROM users WHERE email LIKE 'test-%@example.com'});

# ------------------------------------------------------------
# POST /users — create
# ------------------------------------------------------------
my $created;
$t->post_ok('/api/v1/users' => {%h} => json => {
  email    => 'test-translator@example.com',
  name     => 'Test Translator',
  password => 'password-1',
  role     => 'translator',
})
  ->status_is(201)
  ->json_has('/user/id')
  ->json_is('/user/email', 'test-translator@example.com')
  ->json_is('/user/role',  'translator')
  ->json_is('/user/is_active', 1);

$created = $t->tx->res->json->{user};

# ------------------------------------------------------------
# POST /users — validation errors
# ------------------------------------------------------------
$t->post_ok('/api/v1/users' => {%h} => json => {})
  ->status_is(400)
  ->json_is('/error', 'email_required');

$t->post_ok('/api/v1/users' => {%h} => json => {
  email    => 'test-invalid@example.com',
  name     => 'X',
  password => 'p',
  role     => 'wizard',
})
  ->status_is(400)
  ->json_is('/error', 'invalid_role');

$t->post_ok('/api/v1/users' => {%h} => json => {
  email    => 'test-translator@example.com',
  name     => 'Dup',
  password => 'p',
})
  ->status_is(409)
  ->json_is('/error', 'email_taken');

# ------------------------------------------------------------
# POST /users — CSRF and role guards
# ------------------------------------------------------------
$t->post_ok('/api/v1/users' => json => {  # no CSRF header
  email    => 'test-nocsrf@example.com',
  name     => 'X',
  password => 'p',
})
  ->status_is(403)
  ->json_is('/error', 'csrf_invalid');

# ------------------------------------------------------------
# GET /users — list
# ------------------------------------------------------------
$t->get_ok('/api/v1/users')
  ->status_is(200)
  ->json_is('/users/0/email', $admin_email);  # ordered by id, admin is #1

$t->get_ok('/api/v1/users')
  ->status_is(200)
  ->json_has('/users');

# ------------------------------------------------------------
# PATCH /users/:id — update name
# ------------------------------------------------------------
$t->patch_ok('/api/v1/users/' . $created->{id} => {%h} => json => {
  name => 'Renamed Translator',
})
  ->status_is(200)
  ->json_is('/user/name', 'Renamed Translator');

# ------------------------------------------------------------
# PATCH /users/:id — cannot deactivate self
# ------------------------------------------------------------
$t->patch_ok('/api/v1/users/' . $admin->{id} => {%h} => json => {
  is_active => 0,
})
  ->status_is(409)
  ->json_is('/error', 'cannot_deactivate_self');

# ------------------------------------------------------------
# PATCH /users/:id — cannot remove last admin
# ------------------------------------------------------------
$t->patch_ok('/api/v1/users/' . $admin->{id} => {%h} => json => {
  role => 'translator',
})
  ->status_is(409)
  ->json_is('/error', 'last_admin');

# ------------------------------------------------------------
# PATCH /users/:id — deactivate the test user
# ------------------------------------------------------------
$t->patch_ok('/api/v1/users/' . $created->{id} => {%h} => json => {
  is_active => 0,
})
  ->status_is(200)
  ->json_is('/user/is_active', 0);

# ------------------------------------------------------------
# POST /users/:id/password
# ------------------------------------------------------------
$t->post_ok('/api/v1/users/' . $created->{id} . '/password' => {%h} => json => {
  password => 'password-2',
})
  ->status_is(200)
  ->json_is('/ok', 1);

# old password should not work
$t->post_ok('/api/v1/auth/login' => json => {
  email    => 'test-translator@example.com',
  password => 'password-1',
})
  ->status_is(401);

# ------------------------------------------------------------
# non-admin user cannot reach /users
# (reactivate first, then login)
# ------------------------------------------------------------
$t->patch_ok('/api/v1/users/' . $created->{id} => {%h} => json => {
  is_active => 1,
})
  ->status_is(200);

# logout admin, then login as translator
$t->post_ok('/api/v1/auth/logout' => {%h})
  ->status_is(200);

$t->post_ok('/api/v1/auth/login' => json => {
  email    => 'test-translator@example.com',
  password => 'password-2',
})
  ->status_is(200)
  ->json_has('/csrf_token');

my $tcsrf = $t->tx->res->json->{csrf_token};

$t->get_ok('/api/v1/users')
  ->status_is(403)
  ->json_is('/error', 'forbidden');

# ------------------------------------------------------------
# cleanup: remove test user
# ------------------------------------------------------------
$db->query(q{DELETE FROM users WHERE email LIKE 'test-%@example.com'});

done_testing;
