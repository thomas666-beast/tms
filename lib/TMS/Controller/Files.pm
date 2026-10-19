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

  my $project = $c->db->query('SELECT id FROM projects WHERE id = ?', $project_id)->hash;
  return _err($c, 404, 'project_not_found') unless $project;

  my $format      = $c->param('format')      // '';
  my $source_lang = $c->param('source_lang') // '';
  my $target_lang = $c->param('target_lang') // '';
  my $name        = $c->param('name');
  my $group_id    = $c->param('group_id');
  my $overwrite   = $c->param('overwrite') // 0;

  return _err($c, 400, 'format_required')      unless length $format;
  return _err($c, 400, 'source_lang_required') unless length $source_lang;
  return _err($c, 400, 'target_lang_required') unless length $target_lang;

  my $adapter = eval { TMS::Adapter->for($format) };
  return _err($c, 400, 'unsupported_format') unless $adapter;

  my $upload = $c->req->upload('file');
  return _err($c, 400, 'file_required') unless $upload;

  $name = $upload->filename unless defined $name && length $name;
  return _err($c, 400, 'name_required') unless defined $name && length $name;

  my $existing = $c->db->query(
    'SELECT id, current_revision_id FROM files WHERE project_id = ? AND name = ? AND target_lang = ?',
    $project_id, $name, $target_lang,
  )->hash;

  if ($existing && !$overwrite) {
    return _err($c, 409, 'file_exists');
  }

  my $content = $upload->slurp;
  my $parsed  = eval { $adapter->parse($content) };
  if (!$parsed) {
    my $err = $@ || 'parse failed';
    chomp $err;
    return _err($c, 400, 'invalid_file', { detail => $err });
  }

  my $file;
  eval {
    $c->db->query('BEGIN');

    if ($existing) {
      # Update existing file
      $file = $c->db->query(
        'UPDATE files SET updated_at = now() WHERE id = ? RETURNING id, project_id, name, format, source_lang, target_lang, status, current_revision_id',
        $existing->{id}
      )->hash;

      my $old_keys = $c->db->query(
        'SELECT id, key_path, source_text FROM keys WHERE file_id = ?',
        $file->{id}
      )->hashes;
      
      my %old_by_path = map { $_->{key_path} => $_ } @$old_keys;

      for my $key_path (sort CORE::keys %$parsed) {
        my $text  = $parsed->{$key_path} // '';
        my $count = _word_count($text);

        if (my $old = $old_by_path{$key_path}) {
          if ($old->{source_text} ne $text) {
            $c->db->query(
              'UPDATE keys SET source_text = ?, word_count = ? WHERE id = ?',
              $text, $count, $old->{id}
            );
          }
          delete $old_by_path{$key_path};
        } else {
          $c->db->query(
            'INSERT INTO keys (file_id, key_path, source_text, word_count) VALUES (?, ?, ?, ?)',
            $file->{id}, $key_path, $text, $count
          );
        }
      }

      for my $deleted (values %old_by_path) {
        $c->db->query('DELETE FROM keys WHERE id = ?', $deleted->{id});
      }
    } else {
      # Insert new file
      $file = $c->db->query(
        q{
          INSERT INTO files
            (project_id, group_id, name, format, source_lang, target_lang, status, created_by)
          VALUES (?, ?, ?, ?, ?, ?, 'unassigned', ?)
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

      for my $key_path (sort CORE::keys %$parsed) {
        my $text  = $parsed->{$key_path} // '';
        my $count = _word_count($text);
        $c->db->query(
          'INSERT INTO keys (file_id, key_path, source_text, word_count) VALUES (?, ?, ?, ?)',
          $file->{id}, $key_path, $text, $count,
        );
      }
    }

    $c->db->query('COMMIT');
    1;
  } or do {
    my $err = $@;
    eval { $c->db->query('ROLLBACK') };
    return _err($c, 500, 'file_create_failed', { detail => "$err" });
  };

  _audit($c, 'file.upload', $file->{id}, {
    name        => $file->{name},
    format      => $file->{format},
    overwrite   => $overwrite,
  });

  $c->render(json => {
    file => _public_file($file, { keys_count => scalar(CORE::keys %$parsed) }),
  }, status => $existing ? 200 : 201);
}
sub list_by_project ($c) {
  my $project_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $project_id =~ /\A\d+\z/;

  return undef unless $c->can_access_project($project_id);

  my $project = $c->db->query('SELECT id FROM projects WHERE id = ?', $project_id)->hash;
  return _err($c, 404, 'project_not_found') unless $project;

  my $rows = $c->db->query(
    q{
      SELECT f.id, f.project_id, f.group_id, f.name, f.format,
             f.source_lang, f.target_lang, f.is_source, f.status,
             f.assigned_to_user_id, f.current_revision_id,
             f.created_at, f.updated_at,
             (SELECT count(*) FROM keys k WHERE k.file_id = f.id) AS keys_count,
             (SELECT COALESCE(sum(k.word_count), 0) FROM keys k WHERE k.file_id = f.id) AS words_total,
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
             (SELECT COALESCE(sum(k.word_count), 0) FROM keys k WHERE k.file_id = f.id) AS words_total,
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

  my $counts = $c->db->query(
    q{
      SELECT
        COALESCE(sum(t.word_count) FILTER (WHERE t.action = 'translate' AND t.translated_by_ai = false), 0) AS words_translated,
        COALESCE(sum(t.word_count) FILTER (WHERE t.action = 'correct'), 0) AS words_corrected,
        COALESCE(sum(t.word_count) FILTER (WHERE t.action = 'validate'), 0) AS words_validated,
        COALESCE(sum(t.word_count) FILTER (WHERE t.action = 'self_edit'), 0) AS words_self_edits,
        COALESCE(sum(k.word_count) FILTER (WHERE cur.action = 'ai_draft'), 0) AS words_ai_unchecked,
        COALESCE(sum(k.word_count) FILTER (WHERE cur.status = 'approved'), 0) AS words_approved
        FROM keys k
        LEFT JOIN LATERAL (
          SELECT action, status FROM translations
           WHERE key_id = k.id AND revision_id = ? AND language = ?
           ORDER BY created_at DESC, id DESC LIMIT 1
        ) cur ON true
        LEFT JOIN translations t
          ON t.key_id = k.id
         AND t.revision_id = ?
         AND t.language = ?
       WHERE k.file_id = ?
    },
    $file->{current_revision_id}, $file->{target_lang},
    $file->{current_revision_id}, $file->{target_lang},
    $file->{id},
  )->hash;

  $c->render(json => {
    file => _public_file($file, $counts),
    revision => $revision ? {
      id              => 0 + $revision->{id},
      revision_number => 0 + $revision->{revision_number},
      status          => $revision->{status},
      created_at      => $revision->{created_at},
      approved_at     => $revision->{approved_at},
    } : undef,
  });
}

sub list_keys ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $file_id =~ /\A\d+\z/;

  my $file = $c->db->query(
    'SELECT id, project_id, target_lang, current_revision_id FROM files WHERE id = ?',
    $file_id,
  )->hash;
  return _err($c, 404, 'file_not_found') unless $file;
  return undef unless $c->can_access_project($file->{project_id});

  my $status_filter    = $c->param('status')    // 'all';
  my $attention_filter = $c->param('attention') // '';
  return _err($c, 400, 'invalid_status')
    unless $status_filter =~ /\A(?:all|empty|ai_draft|translated|needs_review|approved|rejected)\z/;
  return _err($c, 400, 'invalid_attention')
    unless $attention_filter =~ /\A(?:|contested|hot|ai_unchecked)\z/;

  my $search_q = $c->param('q') // '';
  my $page     = $c->param('page') // 1;
  my $per_page = $c->param('per_page') // 50;

  $page     = 1   unless $page     =~ /\A\d+\z/ && $page     >= 1;
  $per_page = 50  unless $per_page =~ /\A\d+\z/ && $per_page >= 1;
  $per_page = 200 if $per_page > 200;

  my $with_previous = ($c->param('with_previous') // '') eq '1' ? 1 : 0;

  my $prev_revision_id;
  if ($with_previous) {
    my $prev = $c->db->query(
      q{
        SELECT id FROM file_revisions
         WHERE file_id = ? AND status = 'approved'
         ORDER BY revision_number DESC LIMIT 1
      },
      $file->{id},
    )->hash;
    $prev_revision_id = $prev ? $prev->{id} : undef;
  }

  my $where_extra = '';
  my @where_extra_args;
  if (length $search_q) {
    $where_extra = ' AND (k.key_path ILIKE ? OR COALESCE(k.source_text, \'\') ILIKE ?)';
    push @where_extra_args, "%$search_q%", "%$search_q%";
  }

  my $status_join_filter = '';
  my @status_args;
  if ($status_filter ne 'all') {
    if ($status_filter eq 'empty') {
      $status_join_filter = 'AND t.id IS NULL';
    }
    else {
      $status_join_filter = 'AND t.status = ?';
      push @status_args, $status_filter;
    }
  }

  my $attention_join = '';
  my @attention_args;
  if ($attention_filter eq 'contested') {
    $attention_join = q{
      AND (SELECT count(DISTINCT t2.translated_by_user_id)
             FROM translations t2
             JOIN keys k2 ON k2.id = t2.key_id
            WHERE k2.id = k.id
              AND t2.revision_id = ?
              AND t2.language    = ?
              AND t2.action = 'correct'
              AND t2.translated_by_ai = false) >= 2
    };
    push @attention_args, $file->{current_revision_id}, $file->{target_lang};
  }
  elsif ($attention_filter eq 'hot') {
    $attention_join = q{
      AND (SELECT count(*)
             FROM translations t2
             JOIN keys k2 ON k2.id = t2.key_id
            WHERE k2.id = k.id
              AND t2.revision_id = ?
              AND t2.language    = ?
              AND t2.action IN ('correct','self_edit')
              AND t2.translated_by_ai = false) >= 3
    };
    push @attention_args, $file->{current_revision_id}, $file->{target_lang};
  }
  elsif ($attention_filter eq 'ai_unchecked') {
    $attention_join = q{
      AND t.action = 'ai_draft'
    };
  }

  my $total = $c->db->query(
    qq{
      SELECT count(*) AS n
        FROM keys k
        LEFT JOIN LATERAL (
          SELECT id, status, action FROM translations
           WHERE key_id = k.id AND revision_id = ? AND language = ?
           ORDER BY created_at DESC LIMIT 1
        ) t ON true
       WHERE k.file_id = ?
        $where_extra
        $status_join_filter
        $attention_join
    },
    $file->{current_revision_id}, $file->{target_lang},
    $file->{id},
    @where_extra_args,
    @status_args,
    @attention_args,
  )->hash->{n};

  my $offset = ($page - 1) * $per_page;

  my $rows = $c->db->query(
    qq{
      SELECT k.id, k.key_path, k.source_text, k.word_count,
             t.id           AS translation_id,
             t.text         AS translation_text,
             t.status       AS translation_status,
             t.note         AS translation_note,
             t.translated_by_user_id,
             t.translated_by_ai,
             t.ai_engine,
             t.created_at   AS translation_created_at,
             p.text         AS prev_translation_text,
             p.status       AS prev_translation_status,
             u.name         AS author_name,
             (SELECT count(DISTINCT t3.translated_by_user_id)
                FROM translations t3
               WHERE t3.key_id = k.id
                 AND t3.revision_id = ?
                 AND t3.language    = ?
                 AND t3.action = 'correct'
                 AND t3.translated_by_ai = false) AS distinct_correctors
        FROM keys k
        LEFT JOIN LATERAL (
          SELECT * FROM translations
           WHERE key_id = k.id AND revision_id = ? AND language = ?
           ORDER BY created_at DESC LIMIT 1
        ) t ON true
        LEFT JOIN users u ON u.id = t.translated_by_user_id
        LEFT JOIN LATERAL (
          SELECT * FROM translations
           WHERE key_id = k.id AND revision_id = ? AND language = ?
           ORDER BY created_at DESC LIMIT 1
        ) p ON true
       WHERE k.file_id = ?
        $where_extra
        $status_join_filter
        $attention_join
        ORDER BY k.key_path
        LIMIT $per_page OFFSET $offset
    },
    $file->{current_revision_id}, $file->{target_lang},
    $file->{current_revision_id}, $file->{target_lang},
    $prev_revision_id // -1,       $file->{target_lang},
    $file->{id},
    @where_extra_args,
    @status_args,
    @attention_args,
  )->hashes;

  $c->render(json => {
    file => {
      id          => 0 + $file->{id},
      project_id  => 0 + $file->{project_id},
      target_lang => $file->{target_lang},
    },
    previous_revision_id => $prev_revision_id,
    page        => 0 + $page,
    per_page    => 0 + $per_page,
    total       => 0 + $total,
    total_pages => $total ? int(($total + $per_page - 1) / $per_page) : 0,
    keys        => [ map { _public_key($_, $with_previous) } @$rows ],
  });
}

sub member_stats ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless defined $file_id && $file_id =~ /\A\d+\z/;

  my $file = $c->db->query(
    'SELECT id, project_id, target_lang, current_revision_id FROM files WHERE id = ?',
    $file_id,
  )->hash;
  return _err($c, 404, 'file_not_found') unless $file;
  return undef unless $c->can_access_project($file->{project_id});

  my $revision_id = $file->{current_revision_id};

  my $rows = $c->db->query(
    q{
      SELECT t.translated_by_user_id AS user_id,
             t.action,
             COALESCE(sum(t.word_count), 0) AS words
        FROM translations t
        JOIN keys k ON k.id = t.key_id
       WHERE k.file_id = ?
         AND t.revision_id = ?
         AND t.language = ?
         AND t.translated_by_ai = false
       GROUP BY t.translated_by_user_id, t.action
    },
    $file->{id}, $revision_id, $file->{target_lang},
  )->hashes;

  my %per_user;
  my %total = (
    words_translated   => 0,
    words_corrected    => 0,
    words_validated    => 0,
    words_self_edits   => 0,
  );

  for my $r (@$rows) {
    my $uid = $r->{user_id};
    next unless defined $uid;
    $per_user{$uid} //= {
      words_translated => 0, words_corrected => 0,
      words_validated  => 0, words_self_edits => 0,
    };
    my $w = 0 + ($r->{words} // 0);
    if    ($r->{action} eq 'translate') { $per_user{$uid}{words_translated} += $w; $total{words_translated} += $w }
    elsif ($r->{action} eq 'correct')   { $per_user{$uid}{words_corrected}  += $w; $total{words_corrected}  += $w }
    elsif ($r->{action} eq 'validate')  { $per_user{$uid}{words_validated}  += $w; $total{words_validated}  += $w }
    elsif ($r->{action} eq 'self_edit') { $per_user{$uid}{words_self_edits} += $w; $total{words_self_edits} += $w }
  }

  my $ai_unchecked = $c->db->query(
    q{
      SELECT COALESCE(sum(k.word_count), 0) AS n
        FROM keys k
        JOIN LATERAL (
          SELECT action FROM translations
           WHERE key_id = k.id AND revision_id = ? AND language = ?
           ORDER BY created_at DESC, id DESC LIMIT 1
        ) t ON true
       WHERE k.file_id = ?
         AND t.action = 'ai_draft'
    },
    $revision_id, $file->{target_lang}, $file->{id},
  )->hash->{n};

  my @members;
  if (my @uids = sort { $a <=> $b } CORE::keys %per_user) {
    my $placeholders = join(',', ('?') x @uids);
    my $users = $c->db->query(
      "SELECT id, name, email FROM users WHERE id IN ($placeholders)",
      @uids,
    )->hashes;
    my %by_id = map { $_->{id} => $_ } @$users;
    for my $uid (@uids) {
      my $u = $by_id{$uid};
      push @members, {
        user_id          => 0 + $uid,
        name             => $u ? $u->{name}  : '?',
        email            => $u ? $u->{email} : '?',
        words_translated => $per_user{$uid}{words_translated},
        words_corrected  => $per_user{$uid}{words_corrected},
        words_validated  => $per_user{$uid}{words_validated},
        words_self_edits => $per_user{$uid}{words_self_edits},
      };
    }
  }

  $c->render(json => {
    file_id     => 0 + $file->{id},
    revision_id => 0 + $revision_id,
    members     => \@members,
    total       => {
      words_translated   => 0 + $total{words_translated},
      words_corrected    => 0 + $total{words_corrected},
      words_validated    => 0 + $total{words_validated},
      words_self_edits   => 0 + $total{words_self_edits},
      words_ai_unchecked => 0 + $ai_unchecked,
    },
  });
}

sub assign ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless defined $file_id && $file_id =~ /\A\d+\z/;

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
    q{UPDATE files SET assigned_to_user_id = ?, status = 'assigned' WHERE id = ?},
    $user_id, $file_id,
  );

  $c->db->query(
    'UPDATE assignments SET unassigned_at = now() WHERE file_id = ? AND unassigned_at IS NULL',
    $file_id,
  );
  $c->db->query(
    'INSERT INTO assignments (file_id, user_id, assigned_by) VALUES (?, ?, ?)',
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
  return _err($c, 400, 'invalid_id') unless defined $file_id && $file_id =~ /\A\d+\z/;

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
    'UPDATE assignments SET unassigned_at = now() WHERE file_id = ? AND unassigned_at IS NULL',
    $file_id,
  );

  _audit($c, 'file.unassign', $file_id, { prev_id => 0 + $prev_id });

  $c->render(json => {
    ok   => 1,
    file => { id => 0 + $file_id, assigned_to_user_id => undef, status => 'unassigned' },
  });
}

sub export ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless defined $file_id && $file_id =~ /\A\d+\z/;

  my $file = $c->db->query(
    q{
      SELECT id, project_id, name, format, source_lang, target_lang, current_revision_id
        FROM files WHERE id = ?
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
  } else {
    my $row = $c->db->query(
      q{
        SELECT id FROM file_revisions
         WHERE file_id = ? AND status = 'approved'
         ORDER BY revision_number DESC LIMIT 1
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
          SELECT text, status FROM translations
           WHERE key_id = k.id AND revision_id = ? AND language = ?
           ORDER BY created_at DESC LIMIT 1
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
  $name =~ s/\.[^.]+\z//;
  $name = $name . '.' . $ext;

  my $content_type = $ext eq 'json' ? 'application/json'
                   : $ext eq 'php'  ? 'text/x-php'
                   : $ext eq 'yaml' ? 'text/yaml'
                   : $ext eq 'arb'  ? 'application/json'
                   : $ext eq 'js'   ? 'application/javascript'
                   : 'text/plain';

  $c->res->headers->content_type($content_type);
  $c->res->headers->content_disposition(qq{attachment; filename="$name"});
  $c->render(data => $body);
}

sub _word_count ($text) {
  return 0 unless defined $text;
  my $t = $text;
  $t =~ s/^\s+|\s+$//g;
  return 0 unless length $t;
  my @words = grep { length } split /\s+/, $t;
  return scalar @words;
}

sub _err ($c, $status, $code, $extra = undef) {
  my %payload = (error => $code);
  $payload{detail} = $extra->{detail} if $extra && defined $extra->{detail};
  $c->render(json => \%payload, status => $status);
  return undef;
}

sub _public_file ($f, $counts = undef) {
  my %out = (
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
    words_total         => defined $f->{words_total} ? 0 + $f->{words_total} : 0,
    current_revision_id => defined $f->{current_revision_id} ? 0 + $f->{current_revision_id} : undef,
    assigned_to_user_id => defined $f->{assigned_to_user_id} ? 0 + $f->{assigned_to_user_id} : undef,
    assigned_to_name    => $f->{assigned_to_name},
    assigned_to_email   => $f->{assigned_to_email},
    created_at          => $f->{created_at},
    updated_at          => $f->{updated_at},
  );
  
  if ($counts) {
    for my $k (qw(words_translated words_corrected words_validated
                  words_self_edits words_ai_unchecked words_approved keys_count)) {
      $out{$k} = 0 + ($counts->{$k} // 0) if exists $counts->{$k};
    }
  }
  return \%out;
}

sub _public_key ($r, $with_previous = 0) {
  my %t;
  if (defined $r->{translation_id}) {
    $t{id}                    = 0 + $r->{translation_id};
    $t{text}                  = $r->{translation_text};
    $t{status}                = $r->{translation_status};
    $t{note}                  = $r->{translation_note};
    $t{translated_by_user_id} = defined $r->{translated_by_user_id} ? 0 + $r->{translated_by_user_id} : undef;
    $t{translated_by_ai}      = $r->{translated_by_ai} ? 1 : 0;
    $t{ai_engine}             = $r->{ai_engine};
    $t{author_name}           = $r->{author_name};
    $t{created_at}            = $r->{translation_created_at};
  }

  my %out = (
    id          => 0 + $r->{id},
    key_path    => $r->{key_path},
    source_text => $r->{source_text},
    word_count  => 0 + ($r->{word_count} // 0),
    translation => defined $r->{translation_id} ? \%t : undef,
    contested   => ($r->{distinct_correctors} // 0) >= 2 ? 1 : 0,
    distinct_correctors => 0 + ($r->{distinct_correctors} // 0),
  );

  if ($with_previous) {
    $out{previous_translation} = defined $r->{prev_translation_text}
      ? { text => $r->{prev_translation_text}, status => $r->{prev_translation_status} }
      : undef;
  }
  return \%out;
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

1;
