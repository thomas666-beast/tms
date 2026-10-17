package TMS::Controller::Translations;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::JSON;

sub edit ($c) {
  my $key_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $key_id =~ /\A\d+\z/;

  my $key = $c->db->query(
    q{
      SELECT k.id, k.key_path, k.source_text,
             f.id           AS file_id,
             f.project_id,
             f.target_lang,
             f.status       AS file_status,
             f.assigned_to_user_id,
             f.current_revision_id
        FROM keys k
        JOIN files f ON f.id = k.file_id
       WHERE k.id = ?
    },
    $key_id,
  )->hash;

  return _err($c, 404, 'key_not_found') unless $key;

  return undef unless $c->can_access_project($key->{project_id});

  my $me     = $c->current_user;
  my $member = $c->project_member($key->{project_id});
  my $role   = $member ? $member->{role} : undef;
  my $is_global_admin = $me->{role} eq 'admin';
  my $is_project_admin = $is_global_admin || ($role && $role eq 'admin');
  my $is_project_lead  = $is_project_admin || ($role && $role eq 'lead');
  my $is_assigned      = defined $key->{assigned_to_user_id}
                         && $key->{assigned_to_user_id} == $me->{id};

  return _err($c, 403, 'forbidden')
    unless $is_project_lead || $is_assigned;

  return _err($c, 409, 'revision_not_open')
    unless $c->db->query(
      'SELECT status FROM file_revisions WHERE id = ?',
      $key->{current_revision_id},
    )->hash->{status} eq 'open';

  my $body   = $c->req->json || {};
  my $text   = exists $body->{text}   ? $body->{text}   : undef;
  my $status = exists $body->{status} ? $body->{status} : undef;
  my $note   = exists $body->{note}   ? $body->{note}   : undef;

  return _err($c, 400, 'nothing_to_update')
    unless defined $text || defined $status || defined $note;

  if (defined $text && !length $text) {
    return _err($c, 400, 'text_required');
  }

  if (defined $status) {
    return _err($c, 400, 'invalid_status')
      unless $status =~ /\A(?:translated|needs_review|rejected)\z/;
  }

  if (defined $note && length $note > 2000) {
    return _err($c, 400, 'note_too_long');
  }

  my $current = $c->db->query(
    q{
      SELECT text, status, note
        FROM translations
       WHERE key_id = ? AND revision_id = ? AND language = ?
       ORDER BY created_at DESC LIMIT 1
    },
    $key->{id}, $key->{current_revision_id}, $key->{target_lang},
  )->hash;

  my $final_text   = defined $text   ? $text   : ($current ? $current->{text}   : undef);
  my $final_status = defined $status ? $status : (defined $text ? 'translated' : 'needs_review');
  my $final_note   = defined $note   ? $note   : ($current ? $current->{note}   : undef);

  if ($final_status eq 'translated' && (!defined $final_text || !length $final_text)) {
    return _err($c, 400, 'text_required');
  }

  my $row = $c->db->query(
    q{
      INSERT INTO translations
        (key_id, revision_id, language, text, status, note,
         translated_by_user_id, translated_by_ai)
      VALUES (?, ?, ?, ?, ?, ?, ?, false)
      RETURNING id, text, status, note, translated_by_user_id,
                translated_by_ai, ai_engine, created_at
    },
    $key->{id}, $key->{current_revision_id}, $key->{target_lang},
    $final_text, $final_status, $final_note, $me->{id},
  )->hash;

  _audit($c, 'translation.edit', $key->{id}, {
    key_path    => $key->{key_path},
    revision_id => 0 + $key->{current_revision_id},
    text        => $final_text,
    status      => $final_status,
    note        => $final_note,
  });

  $c->render(json => {
    translation => {
      id                    => 0 + $row->{id},
      text                  => $row->{text},
      status                => $row->{status},
      note                  => $row->{note},
      translated_by_user_id => defined $row->{translated_by_user_id} ? 0 + $row->{translated_by_user_id} : undef,
      translated_by_ai      => $row->{translated_by_ai} ? 1 : 0,
      ai_engine             => $row->{ai_engine},
      created_at            => $row->{created_at},
    },
  });
}

sub history ($c) {
  my $key_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $key_id =~ /\A\d+\z/;

  my $key = $c->db->query(
    q{
      SELECT k.id, k.key_path, f.project_id, f.current_revision_id, f.target_lang
        FROM keys k
        JOIN files f ON f.id = k.file_id
       WHERE k.id = ?
    },
    $key_id,
  )->hash;
  return _err($c, 404, 'key_not_found') unless $key;

  return undef unless $c->can_access_project($key->{project_id});

  my $rows = $c->db->query(
    q{
      SELECT t.id, t.revision_id, t.text, t.status, t.note,
             t.translated_by_user_id, t.translated_by_ai, t.ai_engine,
             t.created_at,
             u.name  AS user_name,
             u.email AS user_email
        FROM translations t
        LEFT JOIN users u ON u.id = t.translated_by_user_id
       WHERE t.key_id = ? AND t.language = ?
       ORDER BY t.created_at DESC, t.id DESC
    },
    $key->{id}, $key->{target_lang},
  )->hashes;

  $c->render(json => {
    history => [ map { _public_entry($_) } @$rows ],
  });
}

sub _err ($c, $status, $code) {
  $c->render(json => { error => $code }, status => $status);
  return undef;
}

sub _public_entry ($r) {
  return {
    id                    => 0 + $r->{id},
    revision_id           => 0 + $r->{revision_id},
    text                  => $r->{text},
    status                => $r->{status},
    note                  => $r->{note},
    translated_by_user_id => defined $r->{translated_by_user_id} ? 0 + $r->{translated_by_user_id} : undef,
    user_name             => $r->{user_name},
    user_email            => $r->{user_email},
    translated_by_ai      => $r->{translated_by_ai} ? 1 : 0,
    ai_engine             => $r->{ai_engine},
    created_at            => $r->{created_at},
  };
}

sub _audit ($c, $action, $key_id, $new) {
  my $me = $c->current_user;
  $c->db->query(
    q{
      INSERT INTO audit_log (user_id, action, entity_type, entity_id, new_value, ip)
      VALUES (?, ?, 'key', ?, ?, ?)
    },
    $me ? $me->{id} : undef,
    $action,
    $key_id,
    defined $new ? Mojo::JSON::encode_json($new) : undef,
    $c->tx->remote_address,
  );
}

1;
