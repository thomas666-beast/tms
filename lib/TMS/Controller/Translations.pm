package TMS::Controller::Translations;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::JSON;
use TMS::Util::Validator;

sub edit ($c) {
  my $key_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless defined $key_id && $key_id =~ /\A\d+\z/;

  my $key = $c->db->query(
    q{
      SELECT k.id, k.key_path, k.source_text, k.word_count,
             f.id           AS file_id,
             f.project_id,
             f.target_lang,
             f.status       AS file_status,
             f.assigned_to_user_id,
             f.current_revision_id,
             f.lock_version
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
  my $is_global_admin  = $me->{role} eq 'admin';
  my $is_project_admin = $is_global_admin || ($role && $role eq 'admin');
  my $is_project_lead  = $is_project_admin || ($role && $role eq 'lead');
  my $is_assigned      = defined $key->{assigned_to_user_id}
                         && $key->{assigned_to_user_id} == $me->{id};

  return _err($c, 403, 'forbidden')
    unless $is_project_lead || $is_assigned;

  my $revision_status = $c->db->query(
    'SELECT status FROM file_revisions WHERE id = ?',
    $key->{current_revision_id},
  )->hash->{status};
  return _err($c, 409, 'revision_not_open')
    unless $revision_status eq 'open';

  my $body   = $c->req->json || {};
  my $text   = exists $body->{text}   ? $body->{text}   : undef;
  my $status = exists $body->{status} ? $body->{status} : undef;
  my $note   = exists $body->{note}   ? $body->{note}   : undef;
  my $force  = $body->{force} // 0;
  my $client_lock = $body->{lock_version};

  return _err($c, 400, 'nothing_to_update')
    unless defined $text || defined $status || defined $note;

  # Lock check
  if (defined $client_lock && $client_lock != $key->{lock_version}) {
    return $c->render(json => { error => 'stale_data' }, status => 409);
  }

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

  my $history = $c->db->query(
    q{
      SELECT id, text, status, note, action, word_count,
             translated_by_user_id, translated_by_ai, ai_engine, created_at
        FROM translations
       WHERE key_id = ? AND revision_id = ? AND language = ?
       ORDER BY created_at, id
    },
    $key->{id}, $key->{current_revision_id}, $key->{target_lang},
  )->hashes;

  my $current = @$history ? $history->[-1] : undef;

  my $final_text   = defined $text   ? $text   : ($current ? $current->{text}   : undef);
  my $final_status = defined $status ? $status : (defined $text ? 'translated' : 'needs_review');
  my $final_note   = defined $note   ? $note   : ($current ? $current->{note}   : undef);

  if ($final_status eq 'translated' && (!defined $final_text || !length $final_text)) {
    return _err($c, 400, 'text_required');
  }

  # Tag validation
  if (!$force && defined $final_text) {
    my $missing = TMS::Util::Validator::missing_tags($key->{source_text}, $final_text);
    if (@$missing) {
      return $c->render(json => { 
        error => 'missing_tags', 
        tags => $missing 
      }, status => 422);
    }
  }

  my $action = _classify(
    new_text  => $final_text,
    author_id => $me->{id},
    history   => $history,
  );

  my $new_lock;
  eval {
    $c->db->query('BEGIN');

    # Re-check lock within transaction
    my $current_lock = $c->db->query('SELECT lock_version FROM files WHERE id = ? FOR UPDATE', $key->{file_id})->hash->{lock_version};
    if (defined $client_lock && $client_lock != $current_lock) {
      die "stale";
    }

    my $row = $c->db->query(
      q{
        INSERT INTO translations
          (key_id, revision_id, language, text, status, note,
           translated_by_user_id, translated_by_ai, ai_engine,
           word_count, action)
        VALUES (?, ?, ?, ?, ?, ?, ?, false, NULL, ?, ?)
        RETURNING id, text, status, note, translated_by_user_id,
                  translated_by_ai, ai_engine, created_at, word_count, action
      },
      $key->{id}, $key->{current_revision_id}, $key->{target_lang},
      $final_text, $final_status, $final_note,
      $me->{id},
      $key->{word_count} // 0,
      $action,
    )->hash;

    $new_lock = $c->db->query(
      'UPDATE files SET lock_version = lock_version + 1 WHERE id = ? RETURNING lock_version',
      $key->{file_id}
    )->hash->{lock_version};

    _audit($c, 'translation.edit', $key->{id}, {
      key_path    => $key->{key_path},
      revision_id => 0 + $key->{current_revision_id},
      text        => $final_text,
      status      => $final_status,
      note        => $final_note,
      action      => $action,
    });

    $c->db->query('COMMIT');

    $c->render(json => {
      translation => {
        id                    => 0 + $row->{id},
        text                  => $row->{text},
        status                => $row->{status},
        note                  => $row->{note},
        translated_by_user_id => 0 + $row->{translated_by_user_id},
        translated_by_ai      => 0,
        ai_engine             => undef,
        word_count            => 0 + $row->{word_count},
        action                => $row->{action},
        created_at            => $row->{created_at},
      },
      lock_version => $new_lock,
    });
    1;
  } or do {
    my $err = $@;
    eval { $c->db->query('ROLLBACK') };
    if ($err =~ /stale/) {
      return $c->render(json => { error => 'stale_data' }, status => 409);
    }
    return _err($c, 500, 'save_failed');
  };
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
      SELECT t.id, t.revision_id, t.text, t.status, t.note, t.action, t.word_count,
             t.translated_by_user_id, t.translated_by_ai, t.ai_engine,
             t.created_at,
             u.name  AS user_name,
             u.email AS user_email
        FROM translations t
        LEFT JOIN users u ON u.id = t.translated_by_user_id
       WHERE t.key_id = ? AND t.revision_id = ? AND t.language = ?
       ORDER BY t.created_at DESC, t.id DESC
    },
    $key->{id}, $key->{current_revision_id}, $key->{target_lang},
  )->hashes;

  my $events = [ map { _public_event($_) } @$rows ];

  $c->render(json => {
    key => {
      id       => 0 + $key->{id},
      key_path => $key->{key_path},
    },
    events  => $events,
    history => $events,
  });
}

sub _err ($c, $status, $code) {
  $c->render(json => { error => $code }, status => $status);
  return undef;
}

sub _normalize ($text) {
  return '' unless defined $text;
  my $t = $text;
  $t =~ s/^\s+|\s+$//g;
  $t =~ s/\s+/ /g;
  return lc $t;
}

sub _classify (%args) {
  my ($new_text, $author_id, $history) = @args{qw(new_text author_id history)};

  return 'translate' unless @$history;

  my $prior    = $history->[-1];
  my $norm_new = _normalize($new_text);

  if ($prior->{translated_by_ai}) {
    return 'translate';
  }

  if (_normalize($prior->{text}) eq $norm_new) {
    return 'validate';
  }

  if (defined $prior->{translated_by_user_id}
      && $prior->{translated_by_user_id} == $author_id) {
    return 'self_edit';
  }

  for my $i (0 .. $#$history - 1) {
    if (_normalize($history->[$i]{text}) eq $norm_new) {
      return 'validate';
    }
  }

  my $already_corrected = 0;
  for my $e (@$history) {
    if ($e->{action} eq 'correct'
        && defined $e->{translated_by_user_id}
        && $e->{translated_by_user_id} == $author_id) {
      $already_corrected = 1;
      last;
    }
  }
  return 'self_edit' if $already_corrected;

  return 'correct';
}

sub _public_event ($r) {
  return {
    id                    => 0 + $r->{id},
    revision_id           => 0 + $r->{revision_id},
    text                  => $r->{text},
    status                => $r->{status},
    note                  => $r->{note},
    action                => $r->{action},
    word_count            => 0 + $r->{word_count},
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
