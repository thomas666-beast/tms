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

my $db = $t->app->pg_pool->db;
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-md-%'});
$db->query(q{DELETE FROM users    WHERE email LIKE 'test-md-%@example.com'});

# reset any leftover in_review files from prior tests so counts are stable
$db->query(q{
  UPDATE files SET status = 'in_progress'
   WHERE status = 'in_review'
});
$db->query(q{
  UPDATE file_revisions SET status = 'open'
   WHERE status = 'in_review'
});

$t->post_ok('/api/v1/auth/login' => json => {
  email    => $admin_email,
  password => $admin_password,
})
  ->status_is(200)
  ->json_has('/csrf_token');
my $csrf = $t->tx->res->json->{csrf_token};
my %h    = ('X-CSRF-Token' => $csrf);

$t->get_ok('/api/v1/me/dashboard')
  ->status_is(200)
  ->json_has('/assigned')
  ->json_has('/reviewable')
  ->json_has('/recent_approved');

$t->post_ok('/api/v1/projects' => {%h} => json => {
  name                => 'MD Project',
  default_source_lang => 'en',
})
  ->status_is(201);
my $project_id = $t->tx->res->json->{project}{id};

my $laravel = "<?php return ['a' => 'A', 'b' => 'B'];";
$t->post_ok("/api/v1/projects/$project_id/files" => {%h} => form => {
  format      => 'laravel',
  source_lang => 'en',
  target_lang => 'fr',
  name        => 'md.php',
  file        => { content => $laravel, filename => 'md.php' },
})
  ->status_is(201);
my $file_id = $t->tx->res->json->{file}{id};

$t->post_ok('/api/v1/users' => {%h} => json => {
  email    => 'test-md-translator@example.com',
  name     => 'MD Translator',
  password => 'password-1',
  role     => 'translator',
})
  ->status_is(201);
my $trans_id = $t->tx->res->json->{user}{id};

$t->post_ok("/api/v1/projects/$project_id/members" => {%h} => json => {
  user_id => $trans_id, role => 'translator',
})
  ->status_is(201);

$t->post_ok("/api/v1/files/$file_id/assign" => {%h} => json => {
  user_id => $trans_id,
})
  ->status_is(200);

$t->post_ok('/api/v1/auth/logout' => {%h})
  ->status_is(200);
$t->post_ok('/api/v1/auth/login' => json => {
  email    => 'test-md-translator@example.com',
  password => 'password-1',
})
  ->status_is(200);
my $tcsrf = $t->tx->res->json->{csrf_token};
my %th    = ('X-CSRF-Token' => $tcsrf);

$t->get_ok('/api/v1/me/dashboard')
  ->status_is(200);
my $trans_dash = $t->tx->res->json;
is scalar(@{ $trans_dash->{assigned} }), 1, 'translator has 1 assigned';
is $trans_dash->{assigned}[0]{id}, $file_id, 'correct file';
is scalar(@{ $trans_dash->{reviewable} }), 0, 'translator has no reviewable';

$t->get_ok("/api/v1/files/$file_id/keys")
  ->status_is(200);
my $key_id = $t->tx->res->json->{keys}[0]{id};

$t->patch_ok("/api/v1/keys/$key_id/translation" => {%th} => json => {
  text => 'X',
})
  ->status_is(200);

$t->post_ok('/api/v1/auth/logout' => {%th})
  ->status_is(200);
$t->post_ok('/api/v1/auth/login' => json => {
  email    => $admin_email,
  password => $admin_password,
})
  ->status_is(200);
my $acsrf = $t->tx->res->json->{csrf_token};
my %ah    = ('X-CSRF-Token' => $acsrf);

$t->post_ok("/api/v1/files/$file_id/submit" => {%ah})
  ->status_is(200);

$t->get_ok('/api/v1/me/dashboard')
  ->status_is(200);
my $admin_dash = $t->tx->res->json;
my ($match) = grep { $_->{id} == $file_id } @{ $admin_dash->{reviewable} };
ok $match, 'created file appears in admin reviewable';
is $match->{approval_count}, 0, 'zero approvals yet';

$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-md-%'});
$db->query(q{DELETE FROM users    WHERE email LIKE 'test-md-%@example.com'});

done_testing;
