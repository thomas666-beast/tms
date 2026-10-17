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

plan skip_all => 'no seeded admin (run script/reset_db.pl first)'
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

$db->query(q{DELETE FROM users WHERE email LIKE 'test-pm-%@example.com'});
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-pm-%'});

$t->post_ok('/api/v1/projects' => {%h} => json => {
  name                => 'Test PM Project',
  default_source_lang => 'en',
})
  ->status_is(201);
my $project_id = $t->tx->res->json->{project}{id};

my ($lead_id, $trans_id);

$t->post_ok('/api/v1/users' => {%h} => json => {
  email    => 'test-pm-lead@example.com',
  name     => 'PM Lead',
  password => 'password-1',
  role     => 'translator',
})
  ->status_is(201);
$lead_id = $t->tx->res->json->{user}{id};

$t->post_ok('/api/v1/users' => {%h} => json => {
  email    => 'test-pm-trans@example.com',
  name     => 'PM Translator',
  password => 'password-1',
  role     => 'translator',
})
  ->status_is(201);
$trans_id = $t->tx->res->json->{user}{id};

$t->get_ok("/api/v1/projects/$project_id/members")
  ->status_is(200);

my $members = $t->tx->res->json->{members};
is scalar(@$members), 1, 'one member initially';
is $members->[0]{user_id}, 0 + $admin->{id}, 'admin is the member';
is $members->[0]{role}, 'admin', 'admin has project role admin';

$t->post_ok("/api/v1/projects/$project_id/members" => {%h} => json => {})
  ->status_is(400)
  ->json_is('/error', 'user_id_required');

$t->post_ok("/api/v1/projects/$project_id/members" => {%h} => json => {
  user_id => $lead_id, role => 'wizard',
})
  ->status_is(400)
  ->json_is('/error', 'invalid_role');

$t->post_ok("/api/v1/projects/$project_id/members" => {%h} => json => {
  user_id => 999999, role => 'translator',
})
  ->status_is(404)
  ->json_is('/error', 'user_not_found');

$t->post_ok("/api/v1/projects/$project_id/members" => {%h} => json => {
  user_id => $lead_id, role => 'lead',
})
  ->status_is(201)
  ->json_is('/ok', 1)
  ->json_is('/changed', 1);

$t->post_ok("/api/v1/projects/$project_id/members" => {%h} => json => {
  user_id => $trans_id, role => 'translator',
})
  ->status_is(201);

$t->post_ok("/api/v1/projects/$project_id/members" => {%h} => json => {
  user_id => $trans_id, role => 'translator',
})
  ->status_is(200)
  ->json_is('/changed', 0);

$t->get_ok("/api/v1/projects/$project_id/members")
  ->status_is(200);
is scalar(@{ $t->tx->res->json->{members} }), 3, 'three members now';

$t->patch_ok("/api/v1/projects/$project_id/members/$lead_id" => {%h} => json => {
  role => 'translator',
})
  ->status_is(200)
  ->json_is('/changed', 1);

$t->patch_ok("/api/v1/projects/$project_id/members/$lead_id" => {%h} => json => {
  role => 'translator',
})
  ->status_is(200)
  ->json_is('/changed', 0);

$t->patch_ok("/api/v1/projects/$project_id/members/" . $admin->{id} => {%h} => json => {
  role => 'translator',
})
  ->status_is(409)
  ->json_is('/error', 'last_project_admin');

$t->delete_ok("/api/v1/projects/$project_id/members/" . $admin->{id} => {%h})
  ->status_is(409)
  ->json_is('/error', 'last_project_admin');

$t->patch_ok("/api/v1/projects/$project_id/members/$lead_id" => {%h} => json => {
  role => 'admin',
})
  ->status_is(200);

$t->patch_ok("/api/v1/projects/$project_id/members/" . $admin->{id} => {%h} => json => {
  role => 'lead',
})
  ->status_is(200)
  ->json_is('/changed', 1);

$t->delete_ok("/api/v1/projects/$project_id/members/$trans_id" => {%h})
  ->status_is(200)
  ->json_is('/ok', 1);

$t->delete_ok("/api/v1/projects/$project_id/members/$trans_id" => {%h})
  ->status_is(404)
  ->json_is('/error', 'member_not_found');

$t->patch_ok("/api/v1/projects/$project_id/members/" . $admin->{id} => {%h} => json => {
  role => 'admin',
})
  ->status_is(200);

$t->patch_ok("/api/v1/projects/$project_id/members/$lead_id" => {%h} => json => {
  role => 'lead',
})
  ->status_is(200);

$t->post_ok('/api/v1/auth/logout' => {%h})
  ->status_is(200);

$t->post_ok('/api/v1/auth/login' => json => {
  email    => 'test-pm-lead@example.com',
  password => 'password-1',
})
  ->status_is(200);
my $lcsrf = $t->tx->res->json->{csrf_token};
my %lh    = ('X-CSRF-Token' => $lcsrf);

$t->get_ok("/api/v1/projects/$project_id/members")
  ->status_is(200);

$t->post_ok("/api/v1/projects/$project_id/members" => {%lh} => json => {
  user_id => $trans_id, role => 'translator',
})
  ->status_is(403)
  ->json_is('/error', 'forbidden');

$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-pm-%'});
$db->query(q{DELETE FROM users    WHERE email LIKE 'test-pm-%@example.com'});

done_testing;
