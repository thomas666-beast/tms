use Mojo::Base -strict;
use Test::More;
use Test::Mojo;

use FindBin;
use lib "$FindBin::Bin/../lib";
use TMS;

my $t = Test::Mojo->new('TMS');

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
# auth flow (skipped if admin not seeded)
# ------------------------------------------------------------
SKIP: {
  my $admin = $t->app->pg_pool->db->query(
    "SELECT id FROM users WHERE email = 'admin\@example.com' AND is_active"
  )->hash;

  skip 'no seeded admin (run script/seed_admin.pl first)', 18 unless $admin;

  $t->post_ok('/api/v1/auth/login' => json => {
    email    => 'admin@example.com',
    password => 'wrong-password',
  })
    ->status_is(401)
    ->json_is('/error', 'invalid_credentials');

  $t->post_ok('/api/v1/auth/login' => json => {
    email    => 'admin@example.com',
    password => 'ChangedAgain!',
  })
    ->status_is(200)
    ->json_has('/user/id')
    ->json_is('/user/email', 'admin@example.com')
    ->json_is('/user/role',  'admin');

  $t->get_ok('/api/v1/auth/me')
    ->status_is(200)
    ->json_is('/user/email', 'admin@example.com')
    ->json_is('/user/role',  'admin');

  $t->post_ok('/api/v1/auth/logout')
    ->status_is(200)
    ->json_is('/ok', 1);

  $t->get_ok('/api/v1/auth/me')
    ->status_is(200)
    ->json_is('/user', undef);
}

done_testing;
