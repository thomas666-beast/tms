use Mojo::Base -strict, -signatures;
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

$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-pm-%'});
$db->query(q{DELETE FROM users    WHERE email LIKE 'test-pm-%@example.com'});

$t->post_ok('/api/v1/projects' => {%h} => json => {
  name                => 'PM Project',
  default_source_lang => 'en',
})
  ->status_is(201);
my $project_id = $t->tx->res->json->{project}{id};

$t->post_ok('/api/v1/users' => {%h} => json => {
  email    => 'test-pm-a@example.com',
  name     => 'PM A',
  password => 'password-1',
  role     => 'translator',
})
  ->status_is(201);
my $user_a = $t->tx->res->json->{user}{id};

$t->post_ok('/api/v1/users' => {%h} => json => {
  email    => 'test-pm-b@example.com',
  name     => 'PM B',
  password => 'password-1',
  role     => 'translator',
})
  ->status_is(201);
my $user_b = $t->tx->res->json->{user}{id};

# candidates: both users should appear (nobody is a member yet)
$t->get_ok("/api/v1/projects/$project_id/candidates")
  ->status_is(200);

my $cands = $t->tx->res->json->{candidates};
my %ids   = map { $_->{id} => 1 } @$cands;
ok $ids{$user_a}, 'user_a is a candidate';
ok $ids{$user_b}, 'user_b is a candidate';

# add A
$t->post_ok("/api/v1/projects/$project_id/members" => {%h} => json => {
  user_id => $user_a, role => 'translator',
})
  ->status_is(201);

# after adding A, A is no longer a candidate, B still is
$t->get_ok("/api/v1/projects/$project_id/candidates")
  ->status_is(200);
$cands = $t->tx->res->json->{candidates};
%ids   = map { $_->{id} => 1 } @$cands;
ok !$ids{$user_a}, 'user_a no longer a candidate';
ok  $ids{$user_b}, 'user_b still a candidate';

# add B as a project admin
$t->post_ok("/api/v1/projects/$project_id/members" => {%h} => json => {
  user_id => $user_b, role => 'admin',
})
  ->status_is(201);

# B (a project admin) can now see candidates endpoint
$t->post_ok('/api/v1/auth/logout' => {%h})
  ->status_is(200);
$t->post_ok('/api/v1/auth/login' => json => {
  email    => 'test-pm-b@example.com',
  password => 'password-1',
})
  ->status_is(200);
my $csrf_b = $t->tx->res->json->{csrf_token};
my %hb     = ('X-CSRF-Token' => $csrf_b);

$t->get_ok("/api/v1/projects/$project_id/candidates")
  ->status_is(200);

# translator A cannot see candidates endpoint
$t->post_ok('/api/v1/auth/logout' => {%hb})
  ->status_is(200);
$t->post_ok('/api/v1/auth/login' => json => {
  email    => 'test-pm-a@example.com',
  password => 'password-1',
})
  ->status_is(200);

$t->get_ok("/api/v1/projects/$project_id/candidates")
  ->status_is(403);

$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-pm-%'});
$db->query(q{DELETE FROM users    WHERE email LIKE 'test-pm-%@example.com'});

done_testing;
