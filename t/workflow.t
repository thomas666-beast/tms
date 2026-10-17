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
$db->query(q{DELETE FROM users WHERE email LIKE 'test-wf-%@example.com'});
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-wf-%'});

# ------------------------------------------------------------
# admin login
# ------------------------------------------------------------
$t->post_ok('/api/v1/auth/login' => json => {
  email    => $admin_email,
  password => $admin_password,
})
  ->status_is(200)
  ->json_has('/csrf_token');
my $acsrf = $t->tx->res->json->{csrf_token};
my %ah    = ('X-CSRF-Token' => $acsrf);

# ------------------------------------------------------------
# setup: project, file, keys, translations
# ------------------------------------------------------------
$t->post_ok('/api/v1/projects' => {%ah} => json => {
  name                => 'WF Project',
  default_source_lang => 'en',
})
  ->status_is(201);
my $project_id = $t->tx->res->json->{project}{id};

my $laravel = <<'PHP';
<?php

return [
    'welcome' => 'Welcome',
    'goodbye' => 'Goodbye',
];
PHP

$t->post_ok("/api/v1/projects/$project_id/files" => {%ah} => form => {
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

# translate all keys as admin
for my $k (@$keys) {
  $t->patch_ok("/api/v1/keys/$k->{id}/translation" => {%ah} => json => {
    text => "FR: $k->{source_text}",
  })
    ->status_is(200);
}

# ------------------------------------------------------------
# submit validation
# ------------------------------------------------------------
# create a translator who is member; they can't submit
$t->post_ok('/api/v1/users' => {%ah} => json => {
  email    => 'test-wf-translator@example.com',
  name     => 'WF Translator',
  password => 'password-1',
  role     => 'translator',
})
  ->status_is(201);
my $trans_id = $t->tx->res->json->{user}{id};

$t->post_ok("/api/v1/projects/$project_id/members" => {%ah} => json => {
  user_id => $trans_id, role => 'translator',
})
  ->status_is(201);

# assign the file to translator
$db->query('UPDATE files SET assigned_to_user_id = ? WHERE id = ?',
  $trans_id, $file_id);

# create lead
$t->post_ok('/api/v1/users' => {%ah} => json => {
  email    => 'test-wf-lead@example.com',
  name     => 'WF Lead',
  password => 'password-1',
  role     => 'lead_translator',
})
  ->status_is(201);
my $lead_id = $t->tx->res->json->{user}{id};

$t->post_ok("/api/v1/projects/$project_id/members" => {%ah} => json => {
  user_id => $lead_id, role => 'lead',
})
  ->status_is(201);

# translator cannot submit
$t->post_ok('/api/v1/auth/logout' => {%ah})
  ->status_is(200);
$t->post_ok('/api/v1/auth/login' => json => {
  email    => 'test-wf-translator@example.com',
  password => 'password-1',
})
  ->status_is(200);
my $tcsrf = $t->tx->res->json->{csrf_token};
my %th    = ('X-CSRF-Token' => $tcsrf);

$t->post_ok("/api/v1/files/$file_id/submit" => {%th})
  ->status_is(403)
  ->json_is('/error', 'forbidden');

# lead can submit
$t->post_ok('/api/v1/auth/logout' => {%th})
  ->status_is(200);
$t->post_ok('/api/v1/auth/login' => json => {
  email    => 'test-wf-lead@example.com',
  password => 'password-1',
})
  ->status_is(200);
my $lcsrf = $t->tx->res->json->{csrf_token};
my %lh    = ('X-CSRF-Token' => $lcsrf);

$t->post_ok("/api/v1/files/$file_id/submit" => {%lh})
  ->status_is(200)
  ->json_is('/revision/status', 'in_review')
  ->json_is('/file/status',     'in_review');

# can't submit again
$t->post_ok("/api/v1/files/$file_id/submit" => {%lh})
  ->status_is(409)
  ->json_is('/error', 'invalid_state');

# edit is blocked while in_review
$t->patch_ok("/api/v1/keys/" . $keys->[0]{id} . "/translation" => {%lh} => json => {
  text => 'change',
})
  ->status_is(409)
  ->json_is('/error', 'revision_not_open');

# ------------------------------------------------------------
# approve flow
# ------------------------------------------------------------
# lead approves once -> still in_review (no admin yet)
$t->post_ok("/api/v1/files/$file_id/approve" => {%lh})
  ->status_is(200)
  ->json_is('/approved',       0)
  ->json_is('/approval_count', 1);

$t->get_ok("/api/v1/files/$file_id/approvals")
  ->status_is(200)
  ->json_is('/approve_count', 1)
  ->json_is('/has_admin',     0)
  ->json_is('/quorum_met',    0);

# lead cannot approve twice
$t->post_ok("/api/v1/files/$file_id/approve" => {%lh})
  ->status_is(409)
  ->json_is('/error', 'already_decided');

# admin approves -> quorum met
$t->post_ok('/api/v1/auth/logout' => {%lh})
  ->status_is(200);
$t->post_ok('/api/v1/auth/login' => json => {
  email    => $admin_email,
  password => $admin_password,
})
  ->status_is(200);
my $acsrf2 = $t->tx->res->json->{csrf_token};
my %ah2    = ('X-CSRF-Token' => $acsrf2);

$t->post_ok("/api/v1/files/$file_id/approve" => {%ah2})
  ->status_is(200)
  ->json_is('/approved',       1)
  ->json_is('/approval_count', 2);

# file and revision status
$t->get_ok("/api/v1/files/$file_id")
  ->status_is(200)
  ->json_is('/file/status',           'approved')
  ->json_is('/revision/status',       'approved');

# ------------------------------------------------------------
# cannot reject an approved revision
# ------------------------------------------------------------
$t->post_ok("/api/v1/files/$file_id/reject" => {%ah2} => json => {
  comment => 'nope',
})
  ->status_is(409)
  ->json_is('/error', 'not_in_review');

# ------------------------------------------------------------
# reject flow (separate file)
# ------------------------------------------------------------
my $laravel2 = "<?php return ['a' => 'A'];";
$t->post_ok("/api/v1/projects/$project_id/files" => {%ah2} => form => {
  format      => 'laravel',
  source_lang => 'en',
  target_lang => 'de',
  name        => 'second.php',
  file        => { content => $laravel2, filename => 'second.php' },
})
  ->status_is(201);
my $file2 = $t->tx->res->json->{file}{id};

$t->get_ok("/api/v1/files/$file2/keys")
  ->status_is(200);
my $k2 = $t->tx->res->json->{keys}[0]{id};

$t->patch_ok("/api/v1/keys/$k2/translation" => {%ah2} => json => {
  text => 'A in German',
})
  ->status_is(200);

$t->post_ok("/api/v1/files/$file2/submit" => {%ah2})
  ->status_is(200);

# reject without comment
$t->post_ok("/api/v1/files/$file2/reject" => {%ah2} => json => {})
  ->status_is(400)
  ->json_is('/error', 'comment_required');

$t->post_ok("/api/v1/files/$file2/reject" => {%ah2} => json => {
  comment => 'needs work',
})
  ->status_is(200)
  ->json_is('/revision/status', 'open')
  ->json_is('/file/status',     'in_progress');

# new revision created
$t->get_ok("/api/v1/files/$file2")
  ->status_is(200)
  ->json_is('/revision/revision_number', 2)
  ->json_is('/revision/status',          'open');

# can now edit again (new revision is open)
$t->patch_ok("/api/v1/keys/$k2/translation" => {%ah2} => json => {
  text => 'A in German v2',
})
  ->status_is(200);

# ------------------------------------------------------------
# own-work guard
# ------------------------------------------------------------
# use the assigned-translator file: file_id is assigned to $trans_id.
# But it's already approved. Let's do this on file2.
$db->query('UPDATE files SET assigned_to_user_id = ? WHERE id = ?',
  $trans_id, $file2);

$t->post_ok("/api/v1/files/$file2/submit" => {%ah2})
  ->status_is(200);

$t->post_ok('/api/v1/auth/logout' => {%ah2})
  ->status_is(200);
$t->post_ok('/api/v1/auth/login' => json => {
  email    => 'test-wf-translator@example.com',
  password => 'password-1',
})
  ->status_is(200);
my $tcsrf2 = $t->tx->res->json->{csrf_token};
my %th2    = ('X-CSRF-Token' => $tcsrf2);

# translator is not a lead -> forbidden (not "cannot approve own work")
$t->post_ok("/api/v1/files/$file2/approve" => {%th2})
  ->status_is(403);

# ------------------------------------------------------------
# cleanup
# ------------------------------------------------------------
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-wf-%'});
$db->query(q{DELETE FROM users    WHERE email LIKE 'test-wf-%@example.com'});

done_testing;
