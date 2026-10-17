package TMS::Controller::Workflow;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::JSON;

sub submit ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless defined $file_id && $file_id =~ /\A\d+\z/;

  my $file = _load_file($c, $file_id);
  return _err($c, 404, 'file_not_found') unless $file;

  return undef unless $c->can_access_project($file->{project_id});
  return _err($c, 403, 'forbidden')
    unless _is_project_lead_or_admin($c, $file->{project_id});

  return _err($c, 409, 'invalid_state')
    unless $file->{file_status} =~ /\A(?:unassigned|assigned|in_progress)\z/;

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
  my $db = $c->db;

  my $ok = eval {
    my $tx = $db->begin;    # rolls back automatically if not committed
    $db->query(
      "UPDATE file_revisions SET status = 'in_review' WHERE id = ?",
      $revision->{id},
    );
    $db->query(
      "UPDATE files SET status = 'in_review' WHERE id = ?",
      $file->{id},
    );
    $tx->commit;
    1;
  };
  unless ($ok) {
    $c->app->log->error("submit failed: $@");
    return _err($c, 500, 'submit_failed');
  }

  my $project = $db->query(
    'SELECT id, name FROM projects WHERE id = ?',
    $file->{project_id},
  )->hash;

  $c->notifier->emit_many(
    $c->notifier->project_leads_and_admins($file->{project_id}, $me->{id}),
    'file_submitted', 'file', $file->{id},
    {
      file_id      => 0 + $file->{id},
      project_id   => 0 + $file->{project_id},
      project_name => $project->{name},
      actor_name   => $me->{name},
      revision_id  => 0 + $revision->{id},
    },
  );

  _audit($c, 'file.submit', $file->{id}, {
    revision_id     => 0 + $revision->{id},
    revision_number => 0 + $revision->{revision_number},
  });

  $c->render(json => {
    ok       => 1,
    file     => { id => 0 + $file->{id}, status => 'in_review' },
    revision => { id => 0 + $revision->{id}, status => 'in_review' },
  });
}

sub approve ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless defined $file_id && $file_id =~ /\A\d+\z/;

  my $file = _load_file($c, $file_id);
  return _err($c, 404, 'file_not_found') unless $file;

  return undef unless $c->can_access_project($file->{project_id});

  my $me   = $c->current_user;
  my $role = _project_role($c, $file->{project_id});
  my $is_lead         = $role && ($role eq 'admin' || $role eq 'lead');
  my $is_global_admin = $me->{role} eq 'admin';
  return _err($c, 403, 'forbidden') unless $is_lead || $is_global_admin;

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

  my $db = $c->db;

  my $already = $db->query(
    'SELECT decision FROM approvals WHERE revision_id = ? AND user_id = ?',
    $revision->{id}, $me->{id},
  )->hash;
  return _err($c, 409, 'already_decided') if $already;

  my ($quorum_ok, $approval_count, $has_admin);

  my $ok = eval {
    my $tx = $db->begin;

    $db->query(
      q{
        INSERT INTO approvals
          (file_id, revision_id, user_id, decision, comment, user_role_at_time)
        VALUES (?, ?, ?, 'approve', ?, ?)
      },
      $file->{id}, $revision->{id}, $me->{id}, $comment, $me->{role},
    );

    my $stats = $db->query(
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
      $db->query(
        "UPDATE file_revisions SET status = 'approved', approved_at = now() WHERE id = ?",
        $revision->{id},
      );
      $db->query(
        "UPDATE files SET status = 'approved' WHERE id = ?",
        $file->{id},
      );
    }

    $tx->commit;
    1;
  };
  unless ($ok) {
    $c->app->log->error("approve failed: $@");
    return _err($c, 500, 'approve_failed');
  }

  if ($quorum_ok) {
    my $project = $db->query(
      'SELECT id, name FROM projects WHERE id = ?',
      $file->{project_id},
    )->hash;

    my @recipients;
    push @recipients, $file->{assigned_to_user_id}
      if defined $file->{assigned_to_user_id};
    push @recipients, @{ $c->notifier->project_admins($file->{project_id}, $me->{id}) };

    $c->notifier->emit_many(
      \@recipients, 'file_approved', 'file', $file->{id},
      {
        file_id      => 0 + $file->{id},
        project_id   => 0 + $file->{project_id},
        project_name => $project->{name},
        actor_name   => $me->{name},
        revision_id  => 0 + $revision->{id},
      },
    );
  }

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

sub reject ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless defined $file_id && $file_id =~ /\A\d+\z/;

  my $file = _load_file($c, $file_id);
  return _err($c, 404, 'file_not_found') unless $file;

  return undef unless $c->can_access_project($file->{project_id});

  my $me   = $c->current_user;
  my $role = _project_role($c, $file->{project_id});
  my $is_lead         = $role && ($role eq 'admin' || $role eq 'lead');
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

  my $db = $c->db;

  my $already = $db->query(
    'SELECT decision FROM approvals WHERE revision_id = ? AND user_id = ?',
    $revision->{id}, $me->{id},
  )->hash;
  return _err($c, 409, 'already_decided') if $already;

  my $new_revision;
  my $ok = eval {
    my $tx = $db->begin;

    $db->query(
      q{
        INSERT INTO approvals
          (file_id, revision_id, user_id, decision, comment, user_role_at_time)
        VALUES (?, ?, ?, 'reject', ?, ?)
      },
      $file->{id}, $revision->{id}, $me->{id}, $comment, $me->{role},
    );

    $db->query(
      "UPDATE file_revisions SET status = 'rejected' WHERE id = ?",
      $revision->{id},
    );

    $new_revision = $db->query(
      q{
        INSERT INTO file_revisions (file_id, revision_number, status, created_by_user_id)
        VALUES (?, ?, 'open', ?)
        RETURNING id, revision_number, status, created_at
      },
      $file->{id}, $revision->{revision_number} + 1, $me->{id},
    )->hash;

    $db->query(
      "UPDATE files SET status = 'in_progress', current_revision_id = ? WHERE id = ?",
      $new_revision->{id}, $file->{id},
    );

    $tx->commit;
    1;
  };
  unless ($ok) {
    $c->app->log->error("reject failed: $@");
    return _err($c, 500, 'reject_failed');
  }

  my $project = $db->query(
    'SELECT id, name FROM projects WHERE id = ?',
    $file->{project_id},
  )->hash;

  my @recipients;
  push @recipients, $file->{assigned_to_user_id}
    if defined $file->{assigned_to_user_id};
  push @recipients, @{ $c->notifier->project_admins($file->{project_id}, $me->{id}) };

  $c->notifier->emit_many(
    \@recipients, 'file_rejected', 'file', $file->{id},
    {
      file_id           => 0 + $file->{id},
      project_id        => 0 + $file->{project_id},
      project_name      => $project->{name},
      actor_name        => $me->{name},
      rejected_revision => 0 + $revision->{id},
      new_revision      => 0 + $new_revision->{id},
      comment           => $comment,
    },
  );

  _audit($c, 'file.reject', $file->{id}, {
    rejected_revision_id => 0 + $revision->{id},
    new_revision_id      => 0 + $new_revision->{id},
    new_revision_number  => 0 + $new_revision->{revision_number},
    comment              => $comment,
  });

  $c->render(json => {
    ok       => 1,
    file     => { id => 0 + $file->{id}, status => 'in_progress' },
    revision => {
      id              => 0 + $new_revision->{id},
      revision_number => 0 + $new_revision->{revision_number},
      status          => 'open',
    },
  });
}

sub approvals ($c) {
  my $file_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless defined $file_id && $file_id =~ /\A\d+\z/;

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

  my $count     = scalar(grep { $_->{decision} eq 'approve' } @$rows);
  my $has_admin = grep { $_->{decision} eq 'approve' && $_->{user_role_at_time} eq 'admin' } @$rows;

  $c->render(json => {
    approvals     => [ map { _public_approval($_) } @$rows ],
    approve_count => $count,
    has_admin     => $has_admin ? 1 : 0,
    quorum_met    => ($count >= 2 && $has_admin) ? 1 : 0,
  });
}

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
    id                => 0 + $a->{id},
    revision_id       => 0 + $a->{revision_id},
    user_id           => 0 + $a->{user_id},
    user_name         => $a->{user_name},
    user_email        => $a->{user_email},
    decision          => $a->{decision},
    comment           => $a->{comment},
    user_role_at_time => $a->{user_role_at_time},
    created_at        => $a->{created_at},
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
