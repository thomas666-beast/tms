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
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-ms-%'});
$db->query(q{DELETE FROM users    WHERE email LIKE 'test-ms-%@example.com'});

$t->post_ok('/api/v1/auth/login' => json => {
  email    => $admin_email,
  password => $admin_password,
})->status_is(200);
my $csrf = $t->tx->res->json->{csrf_token};
my %h    = ('X-CSRF-Token' => $csrf);

$t->post_ok('/api/v1/projects' => {%h} => json => {
  name => 'MS Project', default_source_lang => 'en',
})->status_is(201);
my $project_id = $t->tx->res->json->{project}{id};

my $laravel = "<?php return ['k' => 'Hello world'];";
$t->post_ok("/api/v1/projects/$project_id/files" => {%h} => form => {
  format => 'laravel', source_lang => 'en', target_lang => 'fr',
  name => 'ms.php', file => { content => $laravel, filename => 'ms.php' },
})->status_is(201);
my $file_id = $t->tx->res->json->{file}{id};

$t->get_ok("/api/v1/files/$file_id/keys")->status_is(200);
my $key_id = $t->tx->res->json->{keys}[0]{id};

my $file_row = $db->query('SELECT current_revision_id FROM files WHERE id = ?', $file_id)->hash;
my $rev = $file_row->{current_revision_id};

# admin translates
$t->patch_ok("/api/v1/keys/$key_id/translation" => {%h} => json => {
  text => 'Hello world',
})->status_is(200);

# member_stats: admin has 2 words translated, ai 0, corrected 0
$t->get_ok("/api/v1/files/$file_id/member_stats")->status_is(200);
my $stats = $t->tx->res->json;
my ($admin_row) = grep { $_->{user_id} == $admin->{id} } @{ $stats->{members} };
ok $admin_row, 'admin present';
is $admin_row->{words_translated}, 2, 'admin 2 words translated';
is $admin_row->{words_corrected},  0, 'admin 0 words corrected';
is $stats->{total}{words_translated}, 2, 'total translated 2';
is $stats->{total}{words_ai_unchecked}, 0, 'no AI unchecked';

# file show also returns totals
$t->get_ok("/api/v1/files/$file_id")->status_is(200);
my $f = $t->tx->res->json->{file};
is $f->{words_total},      2, 'words_total 2';
is $f->{words_translated}, 2, 'words_translated 2';
is $f->{words_approved},   0, 'words_approved 0';

$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-ms-%'});
$db->query(q{DELETE FROM users    WHERE email LIKE 'test-ms-%@example.com'});

done_testing;
