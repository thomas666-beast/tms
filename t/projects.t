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
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-project%'});

# ------------------------------------------------------------
# create project — validation
# ------------------------------------------------------------
$t->post_ok('/api/v1/projects' => {%h} => json => {})
  ->status_is(400)
  ->json_is('/error', 'name_required');

$t->post_ok('/api/v1/projects' => {%h} => json => { name => 'X' })
  ->status_is(400)
  ->json_is('/error', 'default_source_lang_required');

# ------------------------------------------------------------
# create project — happy
# ------------------------------------------------------------
$t->post_ok('/api/v1/projects' => {%h} => json => {
  name                => 'Test Project',
  default_source_lang => 'en',
})
  ->status_is(201)
  ->json_has('/project/id')
  ->json_is('/project/name', 'Test Project')
  ->json_is('/project/slug', 'test-project')
  ->json_is('/project/default_source_lang', 'en');

my $project_id = $t->tx->res->json->{project}{id};

# creator should be a member with role admin
my $member = $db->query(
  'SELECT role FROM project_members WHERE project_id = ? AND user_id = ?',
  $project_id, $admin->{id},
)->hash;
is $member->{role}, 'admin', 'creator added as project admin';

# ------------------------------------------------------------
# slug uniqueness
# ------------------------------------------------------------
$t->post_ok('/api/v1/projects' => {%h} => json => {
  name                => 'Test Project',
  default_source_lang => 'en',
})
  ->status_is(201)
  ->json_is('/project/slug', 'test-project-2');

my $project2_id = $t->tx->res->json->{project}{id};

# ------------------------------------------------------------
# list
# ------------------------------------------------------------
$t->get_ok('/api/v1/projects')
  ->status_is(200)
  ->json_has('/projects');

my $list = $t->tx->res->json->{projects};
ok((grep { $_->{id} == $project_id } @$list), 'created project in list');

# ------------------------------------------------------------
# show
# ------------------------------------------------------------
$t->get_ok("/api/v1/projects/$project_id")
  ->status_is(200)
  ->json_is('/project/id', $project_id)
  ->json_has('/members');

# ------------------------------------------------------------
# update
# ------------------------------------------------------------
$t->patch_ok("/api/v1/projects/$project_id" => {%h} => json => {
  name => 'Test Project Renamed',
})
  ->status_is(200)
  ->json_is('/project/name', 'Test Project Renamed');

$t->patch_ok("/api/v1/projects/$project_id" => {%h} => json => {})
  ->status_is(400)
  ->json_is('/error', 'nothing_to_update');

# ------------------------------------------------------------
# show 404 for nonexistent (global admin bypasses membership check,
# so the controller reaches the DB lookup and returns 404)
# ------------------------------------------------------------
$t->get_ok('/api/v1/projects/999999')
  ->status_is(404)
  ->json_is('/error', 'project_not_found');

# ------------------------------------------------------------
# non-admin user can create? should not
# ------------------------------------------------------------
$db->query(q{DELETE FROM users WHERE email = 'test-proj-translator@example.com'});

$t->post_ok('/api/v1/users' => {%h} => json => {
  email    => 'test-proj-translator@example.com',
  name     => 'Proj Translator',
  password => 'password-1',
  role     => 'translator',
})
  ->status_is(201);

my $translator_id = $t->tx->res->json->{user}{id};

# logout admin
$t->post_ok('/api/v1/auth/logout' => {%h})
  ->status_is(200);

# login as translator
$t->post_ok('/api/v1/auth/login' => json => {
  email    => 'test-proj-translator@example.com',
  password => 'password-1',
})
  ->status_is(200);

my $tcsrf = $t->tx->res->json->{csrf_token};
my %th    = ('X-CSRF-Token' => $tcsrf);

# translator cannot create project (403 from require_role admin)
$t->post_ok('/api/v1/projects' => {%th} => json => {
  name => 'X', default_source_lang => 'en',
})
  ->status_is(403)
  ->json_is('/error', 'forbidden');

# translator sees no projects (not a member of any)
$t->get_ok('/api/v1/projects')
  ->status_is(200)
  ->json_is('/projects', []);

# translator cannot see the admin's project
$t->get_ok("/api/v1/projects/$project_id")
  ->status_is(403);

# ------------------------------------------------------------
# cleanup
# ------------------------------------------------------------
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-project%'});
$db->query(q{DELETE FROM users WHERE email = 'test-proj-translator@example.com'});

done_testing;
