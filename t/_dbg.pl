use Mojo::Base -strict, -signatures;
use Test::More;
use Test::Mojo;

use FindBin;
use lib "$FindBin::Bin/../lib";
require "$FindBin::Bin/testlib.pl";
use TMS;
use TMS::Engine;

{
  package FakeEngine;
  sub new { my ($class, %a) = @_; bless {%a}, $class }
  sub name { $_[0]->{name} }
  sub translate { my ($self, $text, $from, $to) = @_; return "AI: $text" }
}

$TMS::Engine::FOR_TEST = sub { FakeEngine->new(name => $_[0]) };

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
$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-act-%'});
$db->query(q{DELETE FROM users    WHERE email LIKE 'test-act-%@example.com'});

$t->post_ok('/api/v1/auth/login' => json => {
  email    => $admin_email,
  password => $admin_password,
})
  ->status_is(200)
  ->json_has('/csrf_token');
my $csrf = $t->tx->res->json->{csrf_token};
my %h    = ('X-CSRF-Token' => $csrf);

$t->post_ok('/api/v1/projects' => {%h} => json => {
  name                => 'Act Project',
  default_source_lang => 'en',
})
  ->status_is(201);
my $project_id = $t->tx->res->json->{project}{id};

my $laravel = "<?php return ['k' => 'Hello world'];";
$t->post_ok("/api/v1/projects/$project_id/files" => {%h} => form => {
  format      => 'laravel',
  source_lang => 'en',
  target_lang => 'fr',
  name        => 'act.php',
  file        => { content => $laravel, filename => 'act.php' },
})
  ->status_is(201);
my $file_id = $t->tx->res->json->{file}{id};

$t->get_ok("/api/v1/files/$file_id/keys")->status_is(200);
my $key_id = $t->tx->res->json->{keys}[0]{id};

my $file_row = $db->query('SELECT current_revision_id FROM files WHERE id = ?', $file_id)->hash;
my $rev      = $file_row->{current_revision_id};

my %uids;
for my $pair ([ u1 => 'test-act-u1@example.com' ], [ u2 => 'test-act-u2@example.com' ], [ u3 => 'test-act-u3@example.com' ]) {
  my ($tag, $email) = @$pair;
  $t->post_ok('/api/v1/users' => {%h} => json => {
    email    => $email,
    name     => uc($tag),
    password => 'password-1',
    role     => 'lead_translator',
  })->status_is(201);
  $uids{$tag} = $t->tx->res->json->{user}{id};
  $t->post_ok("/api/v1/projects/$project_id/members" => {%h} => json => {
    user_id => $uids{$tag}, role => 'lead',
  })->status_is(201);
}

$db->query(
  q{
    INSERT INTO translations
      (key_id, revision_id, language, text, status,
       translated_by_user_id, translated_by_ai, ai_engine,
       word_count, action)
    VALUES (?, ?, 'fr', 'Hello world', 'ai_draft',
            ?, true, 'libretranslate', 2, 'ai_draft')
  },
  $key_id, $rev, $admin->{id},
);

# admin validates AI
$t->patch_ok("/api/v1/keys/$key_id/translation" => {%h} => json => {
  text => 'Hello world',
})
  ->status_is(200)
  ->json_is('/translation/action', 'translate')
  ->json_is('/translation/word_count', 2);

# helper to switch user
my $switch = sub {
  my ($email) = @_;
  $t->post_ok('/api/v1/auth/logout' => {%h});
  $t->post_ok('/api/v1/auth/login' => json => {
    email    => $email,
    password => 'password-1',
  })->status_is(200);
  my $cs = $t->tx->res->json->{csrf_token};
  $t->get_ok('/api/v1/auth/me')->status_is(200);
  return { 'X-CSRF-Token' => $cs };
};

# u1 corrects
my %u1h = %{ $switch->('test-act-u1@example.com') };
$t->patch_ok("/api/v1/keys/$key_id/translation" => {%u1h} => json => {
  text => 'Hello world again',
})
  ->status_is(200)
  ->json_is('/translation/action', 'correct');

# u3 reverts
my %u3h = %{ $switch->('test-act-u3@example.com') };
$t->patch_ok("/api/v1/keys/$key_id/translation" => {%u3h} => json => {
  text => 'Hello world',
})
  ->status_is(200)
  ->json_is('/translation/action', 'validate');

# u2 corrects
my %u2h = %{ $switch->('test-act-u2@example.com') };
$t->patch_ok("/api/v1/keys/$key_id/translation" => {%u2h} => json => {
  text => 'Hello world yeah',
})
  ->status_is(200)
  ->json_is('/translation/action', 'correct');

# u2 self-edit
$t->patch_ok("/api/v1/keys/$key_id/translation" => {%u2h} => json => {
  text => 'Hello world yeah!',
})
  ->status_is(200)
  ->json_is('/translation/action', 'self_edit');

# u2 self-edit again (cap)
$t->patch_ok("/api/v1/keys/$key_id/translation" => {%u2h} => json => {
  text => 'Hello world yeah!!!',
})
  ->status_is(200)
  ->json_is('/translation/action', 'self_edit');

# u1 case/whitespace dodge
my %u1h2 = %{ $switch->('test-act-u1@example.com') };
$t->patch_ok("/api/v1/keys/$key_id/translation" => {%u1h2} => json => {
  text => "  hello   world   yeah!!!  ",
})
  ->status_is(200)
  ->json_is('/translation/action', 'validate');

# history
$t->get_ok("/api/v1/keys/$key_id/history")->status_is(200);
my $events = $t->tx->res->json->{events};
ok scalar(@$events) >= 7, 'history has all events';

my @actions = map { $_->{action} } reverse @$events;
is_deeply [ @actions[0 .. 6] ],
  [qw(ai_draft translate correct validate correct self_edit self_edit)],
  'actions in expected chronological order';

$db->query(q{DELETE FROM projects WHERE slug LIKE 'test-act-%'});
$db->query(q{DELETE FROM users    WHERE email LIKE 'test-act-%@example.com'});

done_testing;
