package TMS::Controller::AiTranslate;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::JSON;
use TMS::Engine;

my $PLACEHOLDER_RE = qr/(?::[A-Za-z_][A-Za-z0-9_]*|\{\{?\s*[A-Za-z0-9_.]+\s*\}?\}|%(?:\d+\$)?[sd])/;

sub key ($c) {
  my $key_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless defined $key_id && $key_id =~ /\A\d+\z/;

  my $key = $c->db->query(
    q{
      SELECT k.id, k.key_path, k.source_text,
             f.id AS file_id, f.project_id, f.target_lang, f.source_lang,
             f.status AS file_status, f.assigned_to_user_id,
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

  my $body        = $c->req->json || {};
  my $engine_name = $body->{engine} // 'libretranslate';

  my $engine = eval { TMS::Engine->for($engine_name) };
  return _err($c, 400, 'unsupported_engine') unless $engine;

  my $source_text = $key->{source_text} // '';
  return _err($c, 400, 'no_source_text') unless length $source_text;

  my $translated = eval {
    $engine->translate($source_text, $key->{source_lang}, $key->{target_lang});
  };
  if (!defined $translated) {
    my $err = $@ || 'translation failed';
    chomp $err;
    return _err($c, 502, 'engine_error', { detail => $err });
  }

  my $status = 'ai_draft';
  my @missing;
  while ($source_text =~ /($PLACEHOLDER_RE)/g) {
    my $ph = $1;
    push @missing, $ph unless index($translated, $ph) >= 0;
  }
  $status = 'needs_review' if @missing;

  my $note;
  if (@missing) {
    $note = 'Placeholders missing: ' . join(', ', @missing);
  }

  my $row = $c->db->query(
    q{
      INSERT INTO translations
        (key_id, revision_id, language, text, status, note,
         translated_by_user_id, translated_by_ai, ai_engine)
      VALUES (?, ?, ?, ?, ?, ?, ?, true, ?)
      RETURNING id, text, status, note, created_at
    },
    $key->{id}, $key->{current_revision_id}, $key->{target_lang},
    $translated, $status, $note, $me->{id}, $engine->name,
  )->hash;

  _audit($c, 'translation.ai', $key->{id}, {
    engine      => $engine->name,
    status      => $status,
    source_lang => $key->{source_lang},
    target_lang => $key->{target_lang},
  });

  $c->render(json => {
    translation => {
      id                    => 0 + $row->{id},
      text                  => $row->{text},
      status                => $row->{status},
      note                  => $row->{note},
      translated_by_user_id => 0 + $me->{id},
      translated_by_ai      => 1,
      ai_engine             => $engine->name,
      created_at            => $row->{created_at},
    },
  });
}

sub file ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless defined $file_id && $file_id =~ /\A\d+\z/;

  my $file = $c->db->query(
    q{
      SELECT id, project_id, target_lang, source_lang,
             status AS file_status, current_revision_id
        FROM files
       WHERE id = ?
    },
    $file_id,
  )->hash;
  return _err($c, 404, 'file_not_found') unless $file;

  return undef unless $c->can_access_project($file->{project_id});

  my $me     = $c->current_user;
  my $member = $c->project_member($file->{project_id});
  my $role   = $member ? $member->{role} : undef;
  my $allowed = $me->{role} eq 'admin'
    || ($role && ($role eq 'admin' || $role eq 'lead'));
  return _err($c, 403, 'forbidden') unless $allowed;

  my $revision_status = $c->db->query(
    'SELECT status FROM file_revisions WHERE id = ?',
    $file->{current_revision_id},
  )->hash->{status};
  return _err($c, 409, 'revision_not_open')
    unless $revision_status eq 'open';

  my $body        = $c->req->json || {};
  my $engine_name = $body->{engine} // 'libretranslate';

  my $engine = eval { TMS::Engine->for($engine_name) };
  return _err($c, 400, 'unsupported_engine') unless $engine;

  my $keys = $c->db->query(
    q{
      SELECT k.id, k.key_path, k.source_text,
             t.id AS translation_id
        FROM keys k
        LEFT JOIN LATERAL (
          SELECT id
            FROM translations
           WHERE key_id = k.id
             AND revision_id = ?
             AND language = ?
           ORDER BY created_at DESC
           LIMIT 1
        ) t ON true
       WHERE k.file_id = ?
       ORDER BY k.key_path
    },
    $file->{current_revision_id}, $file->{target_lang}, $file->{id},
  )->hashes;

  my @todo = grep { !defined $_->{translation_id} && length($_->{source_text} // '') } @$keys;

  my @results;
  my $translated_count = 0;
  my $needs_review_count = 0;
  my $error_count = 0;

  for my $k (@todo) {
    my $translated = eval {
      $engine->translate($k->{source_text}, $file->{source_lang}, $file->{target_lang});
    };
    if (!defined $translated) {
      my $err = $@ || 'translation failed';
      chomp $err;
      push @results, { key_id => 0 + $k->{id}, ok => 0, error => $err };
      $error_count++;
      next;
    }

    my $status = 'ai_draft';
    my @missing;
    while ($k->{source_text} =~ /($PLACEHOLDER_RE)/g) {
      my $ph = $1;
      push @missing, $ph unless index($translated, $ph) >= 0;
    }
    $status = 'needs_review' if @missing;

    my $note;
    if (@missing) {
      $note = 'Placeholders missing: ' . join(', ', @missing);
    }

    my $row = $c->db->query(
      q{
        INSERT INTO translations
          (key_id, revision_id, language, text, status, note,
           translated_by_user_id, translated_by_ai, ai_engine)
        VALUES (?, ?, ?, ?, ?, ?, ?, true, ?)
        RETURNING id
      },
      $k->{id}, $file->{current_revision_id}, $file->{target_lang},
      $translated, $status, $note, $me->{id}, $engine->name,
    )->hash;

    push @results, {
      key_id       => 0 + $k->{id},
      translation_id => 0 + $row->{id},
      status       => $status,
      ok           => 1,
    };
    $translated_count++;
    $needs_review_count++ if $status eq 'needs_review';
  }

  _audit($c, 'file.ai_translate', $file->{id}, {
    engine         => $engine->name,
    translated     => $translated_count,
    needs_review   => $needs_review_count,
    errors         => $error_count,
  });

  $c->render(json => {
    ok             => 1,
    engine         => $engine->name,
    translated     => $translated_count,
    needs_review   => $needs_review_count,
    errors         => $error_count,
    total          => scalar(@todo),
    results        => \@results,
  });
}

sub _err ($c, $status, $code, $extra = undef) {
  my %payload = (error => $code);
  $payload{detail} = $extra->{detail} if $extra && defined $extra->{detail};
  $c->render(json => \%payload, status => $status);
  return undef;
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
