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
# public endpoints
# ------------------------------------------------------------
$t->get_ok('/')
  ->status_is(200)
  ->json_is('/app', 'TMS');

$t->get_ok('/api/v1/health')
  ->status_is(200)
  ->json_is('/status', 'ok')
  ->json_is('/db',     'ok')
  ->json_has('/version')
  ->json_has('/time');

# ------------------------------------------------------------
# auth flow with CSRF
# ------------------------------------------------------------
SKIP: {
  my $admin = $t->app->pg_pool->db->query(
    "SELECT id FROM users WHERE email = ? AND is_active",
    $admin_email,
  )->hash;

  skip 'no seeded admin (run script/reset_db.pl first)', 24
    unless $admin && $admin_password;

  # wrong password
  $t->post_ok('/api/v1/auth/login' => json => {
    email    => $admin_email,
    password => 'wrong-password',
  })
    ->status_is(401)
    ->json_is('/error', 'invalid_credentials');

  # correct password — capture CSRF token
  my $csrf;
  $t->post_ok('/api/v1/auth/login' => json => {
    email    => $admin_email,
    password => $admin_password,
  })
    ->status_is(200)
    ->json_has('/user/id')
    ->json_is('/user/email', $admin_email)
    ->json_is('/user/role',  'admin')
    ->json_has('/csrf_token');

  $csrf = $t->tx->res->json->{csrf_token};
  ok(defined $csrf && length $csrf, 'csrf token present');

  # me returns same CSRF token
  $t->get_ok('/api/v1/auth/me')
    ->status_is(200)
    ->json_is('/user/email', $admin_email)
    ->json_is('/user/role',  'admin')
    ->json_is('/csrf_token', $csrf);

  # mutation without CSRF header → 403
  $t->post_ok('/api/v1/auth/logout')
    ->status_is(403)
    ->json_is('/error', 'csrf_invalid');

  # mutation with CSRF header → 200
  $t->post_ok('/api/v1/auth/logout' => { 'X-CSRF-Token' => $csrf })
    ->status_is(200)
    ->json_is('/ok', 1);

  # after logout, me returns null user
  $t->get_ok('/api/v1/auth/me')
    ->status_is(200)
    ->json_is('/user', undef);
}

done_testing;
