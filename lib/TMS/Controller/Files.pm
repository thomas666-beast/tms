package TMS::Controller::Files;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::JSON;
use TMS::Adapter;

sub upload ($c) {
  my $project_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $project_id =~ /\A\d+\z/;

  return undef unless $c->can_access_project($project_id);

  my $me = $c->current_user;
  my $member = $c->project_member($project_id);
  my $is_project_admin = $me->{role} eq 'admin'
    || ($member && $member->{role} eq 'admin');
  return _err($c, 403, 'forbidden') unless $is_project_admin;

  my $project = $c->db->query(
    'SELECT id FROM projects WHERE id = ?',
    $project_id,
  )->hash;
  return _err($c, 404, 'project_not_found') unless $project;

  my $format      = $c->param('format')      // '';
  my $source_lang = $c->param('source_lang') // '';
  my $target_lang = $c->param('target_lang') // '';
  my $name        = $c->param('name');
  my $group_id    = $c->param('group_id');

  return _err($c, 400, 'format_required')      unless length $format;
  return _err($c, 400, 'source_lang_required') unless length $source_lang;
  return _err($c, 400, 'target_lang_required') unless length $target_lang;

  return _err($c, 400, 'invalid_lang')
    unless $source_lang =~ /\A[A-Za-z][A-Za-z0-9_-]{0,19}\z/
        && $target_lang =~ /\A[A-Za-z][A-Za-z0-9_-]{0,19}\z/;

  my $adapter = eval { TMS::Adapter->for($format) };
  return _err($c, 400, 'unsupported_format') unless $adapter;

  my $upload = $c->req->upload('file');
  return _err($c, 400, 'file_required') unless $upload;
  return _err($c, 400, 'file_empty')    unless $upload->size;

  $name = $upload->filename unless defined $name && length $name;
  return _err($c, 400, 'name_required') unless defined $name && length $name;

  if (defined $group_id) {
    return _err($c, 400, 'invalid_group_id') unless $group_id =~ /\A\d+\z/;
    my $g = $c->db->query(
      'SELECT 1 FROM file_groups WHERE id = ? AND project_id = ?',
      $group_id, $project_id,
    )->hash;
    return _err($c, 404, 'group_not_found') unless $g;
  }

  my $existing = $c->db->query(
    'SELECT 1 FROM files WHERE project_id = ? AND name = ? AND target_lang = ?',
    $project_id, $name, $target_lang,
  )->hash;
  return _err($c, 409, 'file_exists') if $existing;

  my $content = $upload->slurp;
  my $parsed  = eval { $adapter->parse($content) };
  if (!$parsed) {
    my $msg = $@ || 'parse failed';
    chomp $msg;
    return _err($c, 400, 'invalid_file', { detail => $msg });
  }

  my $file;
  eval {
    $c->db->query('BEGIN');

    $file = $c->db->query(
      q{
        INSERT INTO files
          (project_id, group_id, name, format, source_lang, target_lang,
           is_source, status, created_by)
        VALUES (?, ?, ?, ?, ?, ?, false, 'unassigned', ?)
        RETURNING id, project_id, name, format, source_lang, target_lang, status, created_at
      },
      $project_id, $group_id, $name, $format, $source_lang, $target_lang, $me->{id},
    )->hash;

    my $revision = $c->db->query(
      q{
        INSERT INTO file_revisions (file_id, revision_number, status, created_by_user_id)
        VALUES (?, 1, 'open', ?)
        RETURNING id
      },
      $file->{id}, $me->{id},
    )->hash;

    $c->db->query(
      'UPDATE files SET current_revision_id = ? WHERE id = ?',
      $revision->{id}, $file->{id},
    );

    for my $key_path (sort keys %$parsed) {
      $c->db->query(
        'INSERT INTO keys (file_id, key_path, source_text) VALUES (?, ?, ?)',
        $file->{id}, $key_path, $parsed->{$key_path},
      );
    }

    $c->db->query('COMMIT');
    1;
  } or do {
    my $err = $@;
    eval { $c->db->query('ROLLBACK') };
    return _err($c, 500, 'file_create_failed', { detail => "$err" });
  };

  _audit($c, 'file.create', $file->{id}, {
    project_id  => 0 + $project_id,
    name        => $file->{name},
    format      => $file->{format},
    target_lang => $file->{target_lang},
  });

  $c->render(json => {
    file => {
      id          => 0 + $file->{id},
      project_id  => 0 + $file->{project_id},
      name        => $file->{name},
      format      => $file->{format},
      source_lang => $file->{source_lang},
      target_lang => $file->{target_lang},
      status      => $file->{status},
      keys_count  => scalar(keys %$parsed),
      created_at  => $file->{created_at},
    },
  }, status => 201);
}

sub list_by_project ($c) {
  my $project_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $project_id =~ /\A\d+\z/;

  return undef unless $c->can_access_project($project_id);

  my $project = $c->db->query(
    'SELECT id FROM projects WHERE id = ?',
    $project_id,
  )->hash;
  return _err($c, 404, 'project_not_found') unless $project;

  my $rows = $c->db->query(
    q{
      SELECT f.id, f.project_id, f.group_id, f.name, f.format,
             f.source_lang, f.target_lang, f.is_source, f.status,
             f.assigned_to_user_id, f.current_revision_id,
             f.created_at, f.updated_at,
             (SELECT count(*) FROM keys k WHERE k.file_id = f.id) AS keys_count,
             u.name  AS assigned_to_name,
             u.email AS assigned_to_email
        FROM files f
        LEFT JOIN users u ON u.id = f.assigned_to_user_id
       WHERE f.project_id = ?
       ORDER BY f.name, f.target_lang
    },
    $project_id,
  )->hashes;

  $c->render(json => {
    files => [ map { _public_file($_) } @$rows ],
  });
}

sub show ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $file_id =~ /\A\d+\z/;

  my $file = $c->db->query(
    q{
      SELECT f.id, f.project_id, f.group_id, f.name, f.format,
             f.source_lang, f.target_lang, f.is_source, f.status,
             f.assigned_to_user_id, f.current_revision_id,
             f.created_at, f.updated_at,
             (SELECT count(*) FROM keys k WHERE k.file_id = f.id) AS keys_count,
             u.name  AS assigned_to_name,
             u.email AS assigned_to_email
        FROM files f
        LEFT JOIN users u ON u.id = f.assigned_to_user_id
       WHERE f.id = ?
    },
    $file_id,
  )->hash;

  return _err($c, 404, 'file_not_found') unless $file;
  return undef unless $c->can_access_project($file->{project_id});

  my $revision = $c->db->query(
    'SELECT id, revision_number, status, created_at, approved_at
       FROM file_revisions WHERE id = ?',
    $file->{current_revision_id},
  )->hash;

  $c->render(json => {
    file     => _public_file($file),
    revision => $revision ? {
      id              => 0 + $revision->{id},
      revision_number => 0 + $revision->{revision_number},
      status          => $revision->{status},
      created_at      => $revision->{created_at},
      approved_at     => $revision->{approved_at},
    } : undef,
  });
}

sub keys ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $file_id =~ /\A\d+\z/;

  my $file = $c->db->query(
    'SELECT id, project_id, target_lang, current_revision_id FROM files WHERE id = ?',
    $file_id,
  )->hash;
  return _err($c, 404, 'file_not_found') unless $file;
  return undef unless $c->can_access_project($file->{project_id});

  my $status_filter = $c->param('status') // 'all';
  return _err($c, 400, 'invalid_status')
    unless $status_filter =~ /\A(?:all|empty|ai_draft|translated|needs_review|approved|rejected)\z/;

  my $rows = $c->db->query(
    q{
      SELECT k.id, k.key_path, k.source_text,
             t.id           AS translation_id,
             t.text         AS translation_text,
             t.status       AS translation_status,
             t.note         AS translation_note,
             t.translated_by_user_id,
             t.translated_by_ai,
             t.ai_engine,
             t.created_at   AS translation_created_at
        FROM keys k
        LEFT JOIN LATERAL (
          SELECT *
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
    $file->{current_revision_id}, $file->{target_lang}, $file_id,
  )->hashes;

  if ($status_filter ne 'all') {
    if ($status_filter eq 'empty') {
      @$rows = grep { !defined $_->{translation_id} } @$rows;
    } else {
      @$rows = grep {
        defined $_->{translation_id} && ($_->{translation_status} // '') eq $status_filter
      } @$rows;
    }
  }

  $c->render(json => {
    file => {
      id          => 0 + $file->{id},
      project_id  => 0 + $file->{project_id},
      target_lang => $file->{target_lang},
    },
    keys => [ map { _public_key($_) } @$rows ],
  });
}

sub assign ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $file_id =~ /\A\d+\z/;

  my $file = $c->db->query(
    'SELECT id, project_id, status, assigned_to_user_id FROM files WHERE id = ?',
    $file_id,
  )->hash;
  return _err($c, 404, 'file_not_found') unless $file;

  return undef unless $c->can_access_project($file->{project_id});

  my $me = $c->current_user;
  my $member = $c->project_member($file->{project_id});
  my $is_project_admin = $me->{role} eq 'admin'
    || ($member && $member->{role} eq 'admin');
  return _err($c, 403, 'forbidden') unless $is_project_admin;

  return _err($c, 409, 'file_in_review')
    if $file->{status} eq 'in_review' || $file->{status} eq 'approved';

  my $body    = $c->req->json || {};
  my $user_id = $body->{user_id};
  return _err($c, 400, 'user_id_required')
    unless defined $user_id && $user_id =~ /\A\d+\z/;

  my $target = $c->db->query(
    q{
      SELECT u.id, u.name, u.email, u.is_active, m.role AS project_role
        FROM users u
        LEFT JOIN project_members m ON m.user_id = u.id AND m.project_id = ?
       WHERE u.id = ?
    },
    $file->{project_id}, $user_id,
  )->hash;
  return _err($c, 404, 'user_not_found') unless $target;
  return _err($c, 409, 'user_inactive')  unless $target->{is_active};
  return _err($c, 409, 'user_not_project_member') unless defined $target->{project_role};

  my $prev_id = $file->{assigned_to_user_id};

  $c->db->query(
    q{
      UPDATE files
         SET assigned_to_user_id = ?, status = 'assigned'
       WHERE id = ?
    },
    $user_id, $file_id,
  );

  $c->db->query(
    'UPDATE assignments SET unassigned_at = now()
      WHERE file_id = ? AND unassigned_at IS NULL',
    $file_id,
  );
  $c->db->query(
    q{INSERT INTO assignments (file_id, user_id, assigned_by) VALUES (?, ?, ?)},
    $file_id, $user_id, $me->{id},
  );

  my $project = $c->db->query(
    'SELECT id, name FROM projects WHERE id = ?',
    $file->{project_id},
  )->hash;

  $c->notifier->emit(
    $user_id, 'file_assigned', 'file', $file_id,
    {
      file_id      => 0 + $file_id,
      project_id   => 0 + $file->{project_id},
      project_name => $project->{name},
      actor_name   => $me->{name},
    },
  );

  if (defined $prev_id && $prev_id != $user_id) {
    $c->notifier->emit(
      $prev_id, 'file_assigned', 'file', $file_id,
      {
        file_id      => 0 + $file_id,
        project_id   => 0 + $file->{project_id},
        project_name => $project->{name},
        actor_name   => $me->{name},
        reassigned   => 1,
      },
    );
  }

  _audit($c, 'file.assign', $file_id, {
    user_id => 0 + $user_id,
    prev_id => defined $prev_id ? 0 + $prev_id : undef,
  });

  $c->render(json => {
    ok   => 1,
    file => {
      id                  => 0 + $file_id,
      assigned_to_user_id => 0 + $user_id,
      status              => 'assigned',
    },
  });
}

sub unassign ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $file_id =~ /\A\d+\z/;

  my $file = $c->db->query(
    'SELECT id, project_id, status, assigned_to_user_id FROM files WHERE id = ?',
    $file_id,
  )->hash;
  return _err($c, 404, 'file_not_found') unless $file;

  return undef unless $c->can_access_project($file->{project_id});

  my $me = $c->current_user;
  my $member = $c->project_member($file->{project_id});
  my $is_project_admin = $me->{role} eq 'admin'
    || ($member && $member->{role} eq 'admin');
  return _err($c, 403, 'forbidden') unless $is_project_admin;

  return _err($c, 409, 'file_in_review')
    if $file->{status} eq 'in_review' || $file->{status} eq 'approved';

  return _err($c, 409, 'not_assigned') unless defined $file->{assigned_to_user_id};

  my $prev_id = $file->{assigned_to_user_id};

  $c->db->query(
    "UPDATE files SET assigned_to_user_id = NULL, status = 'unassigned' WHERE id = ?",
    $file_id,
  );

  $c->db->query(
    'UPDATE assignments SET unassigned_at = now()
      WHERE file_id = ? AND unassigned_at IS NULL',
    $file_id,
  );

  _audit($c, 'file.unassign', $file_id, {
    prev_id => 0 + $prev_id,
  });

  $c->render(json => {
    ok   => 1,
    file => { id => 0 + $file_id, assigned_to_user_id => undef, status => 'unassigned' },
  });
}

sub _err ($c, $status, $code, $extra = undef) {
  my %payload = (error => $code);
  $payload{detail} = $extra->{detail} if $extra && defined $extra->{detail};
  $c->render(json => \%payload, status => $status);
  return undef;
}

sub _public_file ($f) {
  return {
    id                  => 0 + $f->{id},
    project_id          => 0 + $f->{project_id},
    group_id            => defined $f->{group_id} ? 0 + $f->{group_id} : undef,
    name                => $f->{name},
    format              => $f->{format},
    source_lang         => $f->{source_lang},
    target_lang         => $f->{target_lang},
    is_source           => $f->{is_source} ? 1 : 0,
    status              => $f->{status},
    keys_count          => defined $f->{keys_count} ? 0 + $f->{keys_count} : 0,
    current_revision_id => defined $f->{current_revision_id} ? 0 + $f->{current_revision_id} : undef,
    assigned_to_user_id => defined $f->{assigned_to_user_id} ? 0 + $f->{assigned_to_user_id} : undef,
    assigned_to_name    => $f->{assigned_to_name},
    assigned_to_email   => $f->{assigned_to_email},
    created_at          => $f->{created_at},
    updated_at          => $f->{updated_at},
  };
}

sub _public_key ($r) {
  my %t;
  if (defined $r->{translation_id}) {
    $t{id}                    = 0 + $r->{translation_id};
    $t{text}                  = $r->{translation_text};
    $t{status}                = $r->{translation_status};
    $t{note}                  = $r->{translation_note};
    $t{translated_by_user_id} = defined $r->{translated_by_user_id} ? 0 + $r->{translated_by_user_id} : undef;
    $t{translated_by_ai}      = $r->{translated_by_ai} ? 1 : 0;
    $t{ai_engine}             = $r->{ai_engine};
    $t{created_at}            = $r->{translation_created_at};
  }

  return {
    id          => 0 + $r->{id},
    key_path    => $r->{key_path},
    source_text => $r->{source_text},
    translation => defined $r->{translation_id} ? \%t : undef,
  };
}

sub _audit ($c, $action, $file_id, $new) {
  my $me = $c->current_user;
  $c->db->query(
    q{
      INSERT INTO audit_log (user_id, action, entity_type, entity_id, new_value, ip)
      VALUES (?, ?, 'file', ?, ?, ?)
    },
    $me ? $me->{id} : undef,
    $action,
    $file_id,
    defined $new ? Mojo::JSON::encode_json($new) : undef,
    $c->tx->remote_address,
  );
}

sub export ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless defined $file_id && $file_id =~ /\A\d+\z/;

  my $file = $c->db->query(
    q{
      SELECT id, project_id, name, format, source_lang, target_lang,
             current_revision_id
        FROM files
       WHERE id = ?
    },
    $file_id,
  )->hash;
  return _err($c, 404, 'file_not_found') unless $file;

  return undef unless $c->can_access_project($file->{project_id});

  my $revision_mode = $c->param('revision') // 'current';
  return _err($c, 400, 'invalid_revision')
    unless $revision_mode =~ /\A(?:current|latest_approved)\z/;

  my $revision_id;
  if ($revision_mode eq 'current') {
    $revision_id = $file->{current_revision_id};
  }
  else {
    my $row = $c->db->query(
      q{
        SELECT id
          FROM file_revisions
         WHERE file_id = ? AND status = 'approved'
         ORDER BY revision_number DESC
         LIMIT 1
      },
      $file->{id},
    )->hash;
    return _err($c, 404, 'no_approved_revision') unless $row;
    $revision_id = $row->{id};
  }

  my $adapter = eval { TMS::Adapter->for($file->{format}) };
  return _err($c, 500, 'adapter_failed') unless $adapter;

  my $keys = $c->db->query(
    q{
      SELECT k.key_path, k.source_text,
             t.text   AS translation_text,
             t.status AS translation_status
        FROM keys k
        LEFT JOIN LATERAL (
          SELECT text, status
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
    $revision_id, $file->{target_lang}, $file->{id},
  )->hashes;

  my %flat;
  for my $k (@$keys) {
    my $use = $k->{source_text} // '';
    if (defined $k->{translation_text}
        && $k->{translation_status}
        && $k->{translation_status} =~ /\A(?:translated|approved)\z/) {
      $use = $k->{translation_text};
    }
    $flat{ $k->{key_path} } = $use;
  }

  my $body;
  eval { $body = $adapter->serialize(\%flat); 1 }
    or do {
      my $err = $@ || 'serialize failed';
      chomp $err;
      return _err($c, 500, 'serialize_failed', { detail => $err });
    };

  my $ext  = $adapter->extension;
  my $name = $file->{name};
  $name =~ s/\.[^.]+\z//;    # strip any existing extension
  $name = $name . '.' . $ext;

  my $content_type = $ext eq 'json' ? 'application/json'
                   : $ext eq 'php'  ? 'text/x-php'
                   : $ext eq 'yaml' ? 'text/yaml'
                   : $ext eq 'arb'  ? 'application/json'
                   : 'text/plain';

  $c->res->headers->content_type($content_type);
  $c->res->headers->content_disposition(qq{attachment; filename="$name"});
  $c->render(data => $body);
}

1;
