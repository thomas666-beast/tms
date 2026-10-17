package TMS::Controller::Workflow;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::JSON;

# ------------------------------------------------------------
# POST /api/v1/files/:id/submit
# ------------------------------------------------------------
sub submit ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $file_id =~ /\A\d+\z/;

  my $file = _load_file($c, $file_id);
  return _err($c, 404, 'file_not_found') unless $file;

  return undef unless $c->can_access_project($file->{project_id});

  return _err($c, 403, 'forbidden')
    unless _is_project_lead_or_admin($c, $file->{project_id});

  return _err($c, 409, 'invalid_state')
    unless $file->{file_status} eq 'in_progress';

  my $revision = _load_revision($c, $file->{current_revision_id});
  return _err($c, 409, 'invalid_revision_state')
    unless $revision && $revision->{status} eq 'open';

  my $translated = $c->db->query(
    q{
      SELECT count(*) AS n
        FROM translations
       WHERE revision_id = ?
         AND language    = ?
         AND status IN ('translated','needs_review','approved')
    },
    $revision->{id}, $file->{target_lang},
  )->hash->{n};

  return _err($c, 409, 'no_translations') if $translated == 0;

  my $me = $c->current_user;

  eval {
    $c->db->query('BEGIN');

    $c->db->query(
      "UPDATE file_revisions SET status = 'in_review' WHERE id = ?",
      $revision->{id},
    );
    $c->db->query(
      "UPDATE files SET status = 'in_review' WHERE id = ?",
      $file->{id},
    );

    $c->db->query('COMMIT');
    1;
  } or do {
    my $err = $@;
    eval { $c->db->query('ROLLBACK') };
    return _err($c, 500, 'submit_failed');
  };

  _audit($c, 'file.submit', $file->{id}, {
    revision_id => 0 + $revision->{id},
    revision_number => 0 + $revision->{revision_number},
  });

  $c->render(json => {
    ok       => 1,
    file     => { id => 0 + $file->{id}, status => 'in_review' },
    revision => { id => 0 + $revision->{id}, status => 'in_review' },
  });
}

# ------------------------------------------------------------
# POST /api/v1/files/:id/approve  { comment? }
# ------------------------------------------------------------
sub approve ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $file_id =~ /\A\d+\z/;

  my $file = _load_file($c, $file_id);
  return _err($c, 404, 'file_not_found') unless $file;

  return undef unless $c->can_access_project($file->{project_id});

  my $me = $c->current_user;

  my $role = _project_role($c, $file->{project_id});
  my $is_lead = $role && ($role eq 'admin' || $role eq 'lead');
  my $is_global_admin = $me->{role} eq 'admin';
  return _err($c, 403, 'forbidden') unless $is_lead || $is_global_admin;

  # translator of this file cannot approve it
  if (defined $file->{assigned_to_user_id}
      && $file->{assigned_to_user_id} == $me->{id}) {
    return _err($c, 403, 'cannot_approve_own_work');
  }

  return _err($c, 409, 'not_in_review')
    unless $file->{file_status} eq 'in_review';

  my $revision = _load_revision($c, $file->{current_revision_id});
  return _err($c, 409, 'invalid_revision_state')
    unless $revision && $revision->{status} eq 'in_review';

  my $body    = $c->req->json || {};
  my $comment = $body->{comment};

  my $already = $c->db->query(
    'SELECT decision FROM approvals WHERE revision_id = ? AND user_id = ?',
    $revision->{id}, $me->{id},
  )->hash;
  return _err($c, 409, 'already_decided') if $already;

  my ($quorum_ok, $approval_count, $has_admin);

  eval {
    $c->db->query('BEGIN');

    $c->db->query(
      q{
        INSERT INTO approvals
          (file_id, revision_id, user_id, decision, comment, user_role_at_time)
        VALUES (?, ?, ?, 'approve', ?, ?)
      },
      $file->{id}, $revision->{id}, $me->{id}, $comment, $me->{role},
    );

    my $stats = $c->db->query(
      q{
        SELECT count(*) AS n,
               count(*) FILTER (WHERE user_role_at_time = 'admin') AS admins
          FROM approvals
         WHERE revision_id = ? AND decision = 'approve'
      },
      $revision->{id},
    )->hash;

    $approval_count = 0 + $stats->{n};
    $has_admin      = (0 + $stats->{admins}) > 0;
    $quorum_ok      = $approval_count >= 2 && $has_admin;

    if ($quorum_ok) {
      $c->db->query(
        "UPDATE file_revisions SET status = 'approved', approved_at = now() WHERE id = ?",
        $revision->{id},
      );
      $c->db->query(
        "UPDATE files SET status = 'approved' WHERE id = ?",
        $file->{id},
      );
    }

    $c->db->query('COMMIT');
    1;
  } or do {
    my $err = $@;
    eval { $c->db->query('ROLLBACK') };
    return _err($c, 500, 'approve_failed');
  };

  _audit($c, 'file.approve', $file->{id}, {
    revision_id => 0 + $revision->{id},
    approved    => $quorum_ok ? 1 : 0,
    count       => $approval_count,
  });

  $c->render(json => {
    ok              => 1,
    approved        => $quorum_ok ? 1 : 0,
    approval_count  => $approval_count,
    file_status     => $quorum_ok ? 'approved' : 'in_review',
    revision_status => $quorum_ok ? 'approved' : 'in_review',
  });
}

# ------------------------------------------------------------
# POST /api/v1/files/:id/reject  { comment }
# ------------------------------------------------------------
sub reject ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $file_id =~ /\A\d+\z/;

  my $file = _load_file($c, $file_id);
  return _err($c, 404, 'file_not_found') unless $file;

  return undef unless $c->can_access_project($file->{project_id});

  my $me = $c->current_user;

  my $role = _project_role($c, $file->{project_id});
  my $is_lead = $role && ($role eq 'admin' || $role eq 'lead');
  my $is_global_admin = $me->{role} eq 'admin';
  return _err($c, 403, 'forbidden') unless $is_lead || $is_global_admin;

  return _err($c, 409, 'not_in_review')
    unless $file->{file_status} eq 'in_review';

  my $revision = _load_revision($c, $file->{current_revision_id});
  return _err($c, 409, 'invalid_revision_state')
    unless $revision && $revision->{status} eq 'in_review';

  my $body    = $c->req->json || {};
  my $comment = $body->{comment} // '';
  return _err($c, 400, 'comment_required') unless length $comment;

  my $already = $c->db->query(
    'SELECT decision FROM approvals WHERE revision_id = ? AND user_id = ?',
    $revision->{id}, $me->{id},
  )->hash;
  return _err($c, 409, 'already_decided') if $already;

  my $new_revision;
  eval {
    $c->db->query('BEGIN');

    $c->db->query(
      q{
        INSERT INTO approvals
          (file_id, revision_id, user_id, decision, comment, user_role_at_time)
        VALUES (?, ?, ?, 'reject', ?, ?)
      },
      $file->{id}, $revision->{id}, $me->{id}, $comment, $me->{role},
    );

    $c->db->query(
      "UPDATE file_revisions SET status = 'rejected' WHERE id = ?",
      $revision->{id},
    );

    $new_revision = $c->db->query(
      q{
        INSERT INTO file_revisions (file_id, revision_number, status, created_by_user_id)
        VALUES (?, ?, 'open', ?)
        RETURNING id, revision_number, status, created_at
      },
      $file->{id}, $revision->{revision_number} + 1, $me->{id},
    )->hash;

    $c->db->query(
      "UPDATE files SET status = 'in_progress', current_revision_id = ? WHERE id = ?",
      $new_revision->{id}, $file->{id},
    );

    $c->db->query('COMMIT');
    1;
  } or do {
    my $err = $@;
    eval { $c->db->query('ROLLBACK') };
    return _err($c, 500, 'reject_failed');
  };

  _audit($c, 'file.reject', $file->{id}, {
    rejected_revision_id => 0 + $revision->{id},
    new_revision_id      => 0 + $new_revision->{id},
    new_revision_number  => 0 + $new_revision->{revision_number},
    comment              => $comment,
  });

  $c->render(json => {
    ok      => 1,
    file    => { id => 0 + $file->{id}, status => 'in_progress' },
    revision => {
      id              => 0 + $new_revision->{id},
      revision_number => 0 + $new_revision->{revision_number},
      status          => 'open',
    },
  });
}

# ------------------------------------------------------------
# GET /api/v1/files/:id/approvals
# ------------------------------------------------------------
sub approvals ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $file_id =~ /\A\d+\z/;

  my $file = _load_file($c, $file_id);
  return _err($c, 404, 'file_not_found') unless $file;

  return undef unless $c->can_access_project($file->{project_id});

  my $rows = $c->db->query(
    q{
      SELECT a.id, a.revision_id, a.user_id, a.decision, a.comment,
             a.user_role_at_time, a.created_at,
             u.name AS user_name, u.email AS user_email
        FROM approvals a
        JOIN users u ON u.id = a.user_id
       WHERE a.file_id = ? AND a.revision_id = ?
       ORDER BY a.created_at DESC, a.id DESC
    },
    $file->{id}, $file->{current_revision_id},
  )->hashes;

  my $count = scalar(grep { $_->{decision} eq 'approve' } @$rows);
  my $has_admin = grep { $_->{decision} eq 'approve' && $_->{user_role_at_time} eq 'admin' } @$rows;

  $c->render(json => {
    approvals       => [ map { _public_approval($_) } @$rows ],
    approve_count   => $count,
    has_admin       => $has_admin ? 1 : 0,
    quorum_met      => ($count >= 2 && $has_admin) ? 1 : 0,
  });
}

# ------------------------------------------------------------
# helpers
# ------------------------------------------------------------
sub _err ($c, $status, $code) {
  $c->render(json => { error => $code }, status => $status);
  return undef;
}

sub _load_file ($c, $file_id) {
  return $c->db->query(
    q{
      SELECT id, project_id, target_lang, status AS file_status,
             assigned_to_user_id, current_revision_id
        FROM files
       WHERE id = ?
    },
    $file_id,
  )->hash;
}

sub _load_revision ($c, $revision_id) {
  return unless defined $revision_id;
  return $c->db->query(
    'SELECT id, file_id, revision_number, status FROM file_revisions WHERE id = ?',
    $revision_id,
  )->hash;
}

sub _project_role ($c, $project_id) {
  my $member = $c->project_member($project_id);
  return $member ? $member->{role} : undef;
}

sub _is_project_lead_or_admin ($c, $project_id) {
  my $me = $c->current_user;
  return 1 if $me->{role} eq 'admin';
  my $role = _project_role($c, $project_id);
  return $role && ($role eq 'admin' || $role eq 'lead');
}

sub _public_approval ($a) {
  return {
    id                 => 0 + $a->{id},
    revision_id        => 0 + $a->{revision_id},
    user_id            => 0 + $a->{user_id},
    user_name          => $a->{user_name},
    user_email         => $a->{user_email},
    decision           => $a->{decision},
    comment            => $a->{comment},
    user_role_at_time  => $a->{user_role_at_time},
    created_at         => $a->{created_at},
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

1;
