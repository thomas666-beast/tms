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

my $db = $t->app->pg_pool->db;
$db->query(q{DELETE FROM users WHERE email LIKE 'test-asg-%@example.com'});
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-asg-%'});

$t->post_ok('/api/v1/auth/login' => json => {
  email    => $admin_email,
  password => $admin_password,
})
  ->status_is(200)
  ->json_has('/csrf_token');
my $acsrf = $t->tx->res->json->{csrf_token};
my %ah    = ('X-CSRF-Token' => $acsrf);

# ------------------------------------------------------------
# setup
# ------------------------------------------------------------
$t->post_ok('/api/v1/projects' => {%ah} => json => {
  name                => 'Assignment Project',
  default_source_lang => 'en',
})
  ->status_is(201);
my $project_id = $t->tx->res->json->{project}{id};

my $laravel = "<?php return ['a' => 'A'];";
$t->post_ok("/api/v1/projects/$project_id/files" => {%ah} => form => {
  format      => 'laravel',
  source_lang => 'en',
  target_lang => 'fr',
  name        => 'auth.php',
  file        => { content => $laravel, filename => 'auth.php' },
})
  ->status_is(201);
my $file_id = $t->tx->res->json->{file}{id};

# users
$t->post_ok('/api/v1/users' => {%ah} => json => {
  email    => 'test-asg-translator@example.com',
  name     => 'Translator',
  password => 'password-1',
  role     => 'translator',
})
  ->status_is(201);
my $trans_id = $t->tx->res->json->{user}{id};

$t->post_ok('/api/v1/users' => {%ah} => json => {
  email    => 'test-asg-translator2@example.com',
  name     => 'Translator2',
  password => 'password-1',
  role     => 'translator',
})
  ->status_is(201);
my $trans2_id = $t->tx->res->json->{user}{id};

$t->post_ok('/api/v1/users' => {%ah} => json => {
  email    => 'test-asg-outsider@example.com',
  name     => 'Outsider',
  password => 'password-1',
  role     => 'translator',
})
  ->status_is(201);
my $outsider_id = $t->tx->res->json->{user}{id};

# add both translators as project members
$t->post_ok("/api/v1/projects/$project_id/members" => {%ah} => json => {
  user_id => $trans_id, role => 'translator',
})
  ->status_is(201);
$t->post_ok("/api/v1/projects/$project_id/members" => {%ah} => json => {
  user_id => $trans2_id, role => 'translator',
})
  ->status_is(201);

# ------------------------------------------------------------
# assign validation
# ------------------------------------------------------------
$t->post_ok("/api/v1/files/$file_id/assign" => {%ah} => json => {})
  ->status_is(400)
  ->json_is('/error', 'user_id_required');

$t->post_ok("/api/v1/files/$file_id/assign" => {%ah} => json => {
  user_id => $outsider_id,
})
  ->status_is(409)
  ->json_is('/error', 'user_not_project_member');

# ------------------------------------------------------------
# assign successfully
# ------------------------------------------------------------
$t->post_ok("/api/v1/files/$file_id/assign" => {%ah} => json => {
  user_id => $trans_id,
})
  ->status_is(200)
  ->json_is('/file/assigned_to_user_id', $trans_id)
  ->json_is('/file/status', 'assigned');

# file now shows assigned
$t->get_ok("/api/v1/files/$file_id")
  ->status_is(200)
  ->json_is('/file/assigned_to_user_id', $trans_id)
  ->json_is('/file/assigned_to_email',   'test-asg-translator@example.com');

# notification for assignee
my $notifs = $db->query(
  "SELECT id, type FROM notifications WHERE user_id = ? AND type = 'file_assigned'",
  $trans_id,
)->hashes;
is scalar(@$notifs), 1, 'assignee notified';

# ------------------------------------------------------------
# reassign to translator2 -> notifications to both
# ------------------------------------------------------------
$t->post_ok("/api/v1/files/$file_id/assign" => {%ah} => json => {
  user_id => $trans2_id,
})
  ->status_is(200);

my $n1 = $db->query(
  "SELECT count(*) AS n FROM notifications WHERE user_id = ? AND type = 'file_assigned'",
  $trans_id,
)->hash->{n};
my $n2 = $db->query(
  "SELECT count(*) AS n FROM notifications WHERE user_id = ? AND type = 'file_assigned'",
  $trans2_id,
)->hash->{n};
is 0 + $n1, 2, 'first translator notified again (reassigned)';
is 0 + $n2, 1, 'second translator notified';

# ------------------------------------------------------------
# unassign
# ------------------------------------------------------------
$t->post_ok("/api/v1/files/$file_id/unassign" => {%ah})
  ->status_is(200)
  ->json_is('/file/status', 'unassigned');

$t->get_ok("/api/v1/files/$file_id")
  ->status_is(200)
  ->json_is('/file/assigned_to_user_id', undef);

# unassign when nothing assigned -> 409
$t->post_ok("/api/v1/files/$file_id/unassign" => {%ah})
  ->status_is(409)
  ->json_is('/error', 'not_assigned');

# ------------------------------------------------------------
# notifications endpoint
# ------------------------------------------------------------
$t->get_ok('/api/v1/notifications')
  ->status_is(200);

my $mynots = $t->tx->res->json->{notifications};
ok scalar(@$mynots) >= 0, 'notifications list returns array';

# assign to trans, then login as trans and mark read
$t->post_ok("/api/v1/files/$file_id/assign" => {%ah} => json => {
  user_id => $trans_id,
})
  ->status_is(200);

$t->post_ok('/api/v1/auth/logout' => {%ah})
  ->status_is(200);
$t->post_ok('/api/v1/auth/login' => json => {
  email    => 'test-asg-translator@example.com',
  password => 'password-1',
})
  ->status_is(200);
my $tcsrf = $t->tx->res->json->{csrf_token};
my %th    = ('X-CSRF-Token' => $tcsrf);

$t->get_ok('/api/v1/notifications')
  ->status_is(200);

my $mine = $t->tx->res->json;
ok $mine->{unread_count} >= 1, 'has unread';

# mark one as read
my $first = $mine->{notifications}[0];
$t->post_ok("/api/v1/notifications/$first->{id}/read" => {%th})
  ->status_is(200)
  ->json_is('/ok', 1);

# mark all
$t->post_ok('/api/v1/notifications/read_all' => {%th})
  ->status_is(200)
  ->json_has('/updated');

$t->get_ok('/api/v1/notifications')
  ->status_is(200)
  ->json_is('/unread_count', 0);

# ------------------------------------------------------------
# translator cannot assign (not admin)
# ------------------------------------------------------------
$t->post_ok("/api/v1/files/$file_id/assign" => {%th} => json => {
  user_id => $trans2_id,
})
  ->status_is(403)
  ->json_is('/error', 'forbidden');

# ------------------------------------------------------------
# cleanup
# ------------------------------------------------------------
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-asg-%'});
$db->query(q{DELETE FROM users    WHERE email LIKE 'test-asg-%@example.com'});

done_testing;
