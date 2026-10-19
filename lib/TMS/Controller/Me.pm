package TMS::Controller::Me;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Authen::Passphrase::BlowfishCrypt;

sub dashboard ($c) {
  my $me = $c->current_user;

  my $assigned = $c->db->query(
    q{
      SELECT f.id, f.name, f.format, f.status, f.target_lang, f.source_lang, f.updated_at,
             p.id AS project_id, p.name AS project_name
        FROM files f
        JOIN projects p ON p.id = f.project_id
       WHERE f.assigned_to_user_id = ?
         AND f.status IN ('assigned','in_progress','in_review')
       ORDER BY f.updated_at DESC
       LIMIT 10
    },
    $me->{id},
  )->hashes;

  my $reviewable = $c->db->query(
    q{
      SELECT DISTINCT f.id, f.name, f.status, f.target_lang, f.updated_at,
             p.id AS project_id, p.name AS project_name,
             (SELECT count(*) FROM approvals a
                WHERE a.revision_id = f.current_revision_id
                  AND a.decision = 'approve') AS approval_count
        FROM files f
        JOIN projects p ON p.id = f.project_id
        LEFT JOIN project_members m ON m.project_id = f.project_id AND m.user_id = ?
       WHERE f.status = 'in_review'
         AND ( ? = 'admin' OR m.role IN ('admin','lead') )
       ORDER BY f.updated_at DESC
       LIMIT 10
    },
    $me->{id}, $me->{role},
  )->hashes;

  my $approved = $c->db->query(
    q{
      SELECT DISTINCT f.id, f.name, f.status, f.target_lang, f.updated_at,
             p.id AS project_id, p.name AS project_name
        FROM files f
        JOIN projects p ON p.id = f.project_id
        LEFT JOIN approvals a ON a.file_id = f.id AND a.user_id = ?
       WHERE f.status = 'approved'
         AND (f.assigned_to_user_id = ? OR a.id IS NOT NULL)
       ORDER BY f.updated_at DESC
       LIMIT 10
    },
    $me->{id}, $me->{id},
  )->hashes;

  # Stats
  my $stats = $c->db->query(
    q{
      SELECT
        COALESCE(sum(word_count) FILTER (WHERE action = 'translate'), 0) AS words_translated,
        COALESCE(sum(word_count) FILTER (WHERE action = 'correct'), 0) AS words_corrected
        FROM translations
       WHERE translated_by_user_id = ?
         AND translated_by_ai = false
    },
    $me->{id},
  )->hash;

  # Recent Activity (last 10 events from accessible projects)
  my $recent = $c->db->query(
    q{
      SELECT a.id, a.action, a.new_value, a.created_at,
             u.name AS user_name,
             f.name AS file_name, p.name AS project_name
        FROM audit_log a
        LEFT JOIN users u ON u.id = a.user_id
        LEFT JOIN files f ON a.entity_type = 'file' AND a.entity_id = f.id
        LEFT JOIN projects p ON f.project_id = p.id
       WHERE (a.entity_type = 'file' AND f.project_id IN (
                 SELECT project_id FROM project_members WHERE user_id = ?
                 UNION
                 SELECT id FROM projects WHERE ? = 'admin'
              ))
         AND a.action IN ('file.submit', 'file.approve', 'file.reject', 'translation.ai')
       ORDER BY a.created_at DESC
       LIMIT 10
    },
    $me->{id}, $me->{role},
  )->hashes;

  $c->render(json => {
    assigned        => [ map { _row($_) } @$assigned ],
    reviewable      => [ map { _row($_) } @$reviewable ],
    recent_approved => [ map { _row($_) } @$approved ],
    recent_activity => [ map { _activity_row($_) } @$recent ],
    stats => {
      words_translated => 0 + $stats->{words_translated},
      words_corrected  => 0 + $stats->{words_corrected},
    },
  });
}

sub _activity_row ($r) {
  my $payload = $r->{new_value};
  if (defined $payload && !ref $payload) {
    require Mojo::JSON;
    $payload = eval { Mojo::JSON::decode_json($payload) };
  }
  return {
    id           => 0 + $r->{id},
    action       => $r->{action},
    user_name    => $r->{user_name} // 'System',
    file_name    => $r->{file_name} // 'Unknown',
    project_name => $r->{project_name} // '',
    word_count   => $payload && $payload->{word_count} ? 0 + $payload->{word_count} : 0,
    created_at   => $r->{created_at},
  };
}

sub change_password ($c) {
  my $me = $c->current_user;
  my $body = $c->req->json || {};
  my $old = $body->{old_password} // '';
  my $new = $body->{new_password} // '';

  return _err($c, 400, 'old_password_required') unless length $old;
  return _err($c, 400, 'new_password_required') unless length $new;

  my $u = $c->db->query(
    'SELECT password_hash FROM users WHERE id = ?',
    $me->{id},
  )->hash;

  my $ok = eval {
    my $pp = Authen::Passphrase::BlowfishCrypt->from_rfc2307($u->{password_hash});
    $pp->match($old) ? 1 : 0;
  } || 0;

  return _err($c, 400, 'invalid_old_password') unless $ok;

  my $hash = Authen::Passphrase::BlowfishCrypt->new(
    cost        => 10,
    salt_random => 1,
    passphrase  => $new,
  )->as_rfc2307;

  $c->db->query(
    'UPDATE users SET password_hash = ? WHERE id = ?',
    $hash, $me->{id},
  );

  # Revoke all sessions EXCEPT the current one
  my $sid = $c->stash('session_id');
  $c->db->query(
    'UPDATE sessions SET revoked_at = now() WHERE user_id = ? AND id <> ? AND revoked_at IS NULL',
    $me->{id}, $sid // '',
  );

  $c->render(json => { ok => 1 });
}

sub _row ($r) {
  my %out = (
    id           => 0 + $r->{id},
    name         => $r->{name},
    status       => $r->{status},
    target_lang  => $r->{target_lang},
    project_id   => 0 + $r->{project_id},
    project_name => $r->{project_name},
  );
  $out{approval_count} = 0 + $r->{approval_count} if exists $r->{approval_count};
  return \%out;
}

sub _err ($c, $status, $code) {
  $c->render(json => { error => $code }, status => $status);
  return undef;
}

sub get_preferences ($c) {
  my $me = $c->current_user;
  my $prefs = $c->db->query(
    'SELECT notification_preferences FROM users WHERE id = ?',
    $me->{id},
  )->hash->{notification_preferences} // {};
  
  if (!ref $prefs) {
    require Mojo::JSON;
    $prefs = eval { Mojo::JSON::decode_json($prefs) } || {};
  }

  $c->render(json => { preferences => $prefs });
}

sub set_preferences ($c) {
  my $me = $c->current_user;
  my $body = $c->req->json || {};
  my $prefs = $body->{preferences} || {};

  $c->db->query(
    'UPDATE users SET notification_preferences = ?::jsonb WHERE id = ?',
    Mojo::JSON::encode_json($prefs), $me->{id},
  );

  $c->render(json => { ok => 1 });
}

1;
