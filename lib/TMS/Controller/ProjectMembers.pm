package TMS::Controller::ProjectMembers;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub list ($c) {
  my $project_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless defined $project_id && $project_id =~ /\A\d+\z/;

  return undef unless $c->can_access_project($project_id);

  my $project = _project($c, $project_id);
  return _err($c, 404, 'project_not_found') unless $project;

  my $rows = $c->db->query(
    q{
      SELECT m.user_id, m.role, m.added_at,
             u.email, u.name, u.is_active
        FROM project_members m
        JOIN users u ON u.id = m.user_id
       WHERE m.project_id = ?
       ORDER BY m.added_at, m.user_id
    },
    $project_id,
  )->hashes;

  $c->render(json => {
    members => [ map { _public_member($_) } @$rows ],
  });
}

sub candidates ($c) {
  my $project_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless defined $project_id && $project_id =~ /\A\d+\z/;

  return undef unless $c->can_access_project($project_id);

  my $me = $c->current_user;
  my $member = $c->project_member($project_id);
  my $is_project_admin = $me->{role} eq 'admin'
    || ($member && $member->{role} eq 'admin');
  return _err($c, 403, 'forbidden') unless $is_project_admin;

  my $rows = $c->db->query(
    q{
      SELECT u.id, u.email, u.name, u.role, u.is_active
        FROM users u
        LEFT JOIN project_members m
          ON m.user_id = u.id AND m.project_id = ?
       WHERE u.is_active
         AND m.user_id IS NULL
       ORDER BY u.name, u.id
    },
    $project_id,
  )->hashes;

  $c->render(json => {
    candidates => [ map {
      {
        id     => 0 + $_->{id},
        email  => $_->{email},
        name   => $_->{name},
        role   => $_->{role},
      }
    } @$rows ],
  });
}

sub add ($c) {
  my $project_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless defined $project_id && $project_id =~ /\A\d+\z/;

  return undef unless $c->can_access_project($project_id);

  my $me = $c->current_user;
  my $member = $c->project_member($project_id);
  my $is_project_admin = $me->{role} eq 'admin'
    || ($member && $member->{role} eq 'admin');
  return _err($c, 403, 'forbidden') unless $is_project_admin;

  my $project = _project($c, $project_id);
  return _err($c, 404, 'project_not_found') unless $project;

  my $body     = $c->req->json || {};
  my $user_id  = $body->{user_id};
  my $role     = $body->{role} // 'translator';

  return _err($c, 400, 'user_id_required')
    unless defined $user_id && $user_id =~ /\A\d+\z/;
  return _err($c, 400, 'invalid_role')
    unless $role =~ /\A(?:admin|lead|translator)\z/;

  my $target = $c->db->query(
    'SELECT id, is_active FROM users WHERE id = ?',
    $user_id,
  )->hash;
  return _err($c, 404, 'user_not_found') unless $target;
  return _err($c, 409, 'user_inactive') unless $target->{is_active};

  my $existing = $c->db->query(
    'SELECT role FROM project_members WHERE project_id = ? AND user_id = ?',
    $project_id, $user_id,
  )->hash;

  if ($existing) {
    if ($existing->{role} ne $role) {
      if ($existing->{role} eq 'admin' && $role ne 'admin') {
        my $admins = $c->db->query(
          q{SELECT count(*) AS n FROM project_members WHERE project_id = ? AND role = 'admin' AND user_id <> ?},
          $project_id, $user_id,
        )->hash->{n};
        return _err($c, 409, 'last_project_admin') if $admins == 0;
      }
      $c->db->query(
        'UPDATE project_members SET role = ? WHERE project_id = ? AND user_id = ?',
        $role, $project_id, $user_id,
      );
      _audit($c, 'project.member.update', $project_id,
        { user_id => 0 + $user_id, role => $existing->{role} },
        { user_id => 0 + $user_id, role => $role },
      );
    }
    return $c->render(json => { ok => 1, changed => 0 });
  }

  $c->db->query(
    q{
      INSERT INTO project_members (project_id, user_id, role, added_by)
      VALUES (?, ?, ?, ?)
    },
    $project_id, $user_id, $role, $me->{id},
  );

  _audit($c, 'project.member.add', $project_id, undef,
    { user_id => 0 + $user_id, role => $role },
  );

  $c->render(json => { ok => 1, changed => 1 }, status => 201);
}

sub update ($c) {
  my $project_id = $c->param('id');
  my $user_id    = $c->param('user_id');

  return _err($c, 400, 'invalid_id')
    unless defined $project_id && $project_id =~ /\A\d+\z/
        && defined $user_id    && $user_id    =~ /\A\d+\z/;

  return undef unless $c->can_access_project($project_id);

  my $me = $c->current_user;
  my $member = $c->project_member($project_id);
  my $is_project_admin = $me->{role} eq 'admin'
    || ($member && $member->{role} eq 'admin');
  return _err($c, 403, 'forbidden') unless $is_project_admin;

  my $project = _project($c, $project_id);
  return _err($c, 404, 'project_not_found') unless $project;

  my $body = $c->req->json || {};
  my $role = $body->{role};
  return _err($c, 400, 'invalid_role')
    unless defined $role && $role =~ /\A(?:admin|lead|translator)\z/;

  my $existing = $c->db->query(
    'SELECT role FROM project_members WHERE project_id = ? AND user_id = ?',
    $project_id, $user_id,
  )->hash;
  return _err($c, 404, 'member_not_found') unless $existing;

  return $c->render(json => { ok => 1, changed => 0 })
    if $existing->{role} eq $role;

  if ($existing->{role} eq 'admin' && $role ne 'admin') {
    my $admins = $c->db->query(
      q{SELECT count(*) AS n FROM project_members WHERE project_id = ? AND role = 'admin' AND user_id <> ?},
      $project_id, $user_id,
    )->hash->{n};
    return _err($c, 409, 'last_project_admin') if $admins == 0;
  }

  $c->db->query(
    'UPDATE project_members SET role = ? WHERE project_id = ? AND user_id = ?',
    $role, $project_id, $user_id,
  );

  _audit($c, 'project.member.update', $project_id,
    { user_id => 0 + $user_id, role => $existing->{role} },
    { user_id => 0 + $user_id, role => $role },
  );

  $c->render(json => { ok => 1, changed => 1 });
}

sub remove ($c) {
  my $project_id = $c->param('id');
  my $user_id    = $c->param('user_id');

  return _err($c, 400, 'invalid_id')
    unless defined $project_id && $project_id =~ /\A\d+\z/
        && defined $user_id    && $user_id    =~ /\A\d+\z/;

  return undef unless $c->can_access_project($project_id);

  my $me = $c->current_user;
  my $member = $c->project_member($project_id);
  my $is_project_admin = $me->{role} eq 'admin'
    || ($member && $member->{role} eq 'admin');
  return _err($c, 403, 'forbidden') unless $is_project_admin;

  my $project = _project($c, $project_id);
  return _err($c, 404, 'project_not_found') unless $project;

  my $existing = $c->db->query(
    'SELECT role FROM project_members WHERE project_id = ? AND user_id = ?',
    $project_id, $user_id,
  )->hash;
  return _err($c, 404, 'member_not_found') unless $existing;

  if ($existing->{role} eq 'admin') {
    my $admins = $c->db->query(
      q{SELECT count(*) AS n FROM project_members WHERE project_id = ? AND role = 'admin' AND user_id <> ?},
      $project_id, $user_id,
    )->hash->{n};
    return _err($c, 409, 'last_project_admin') if $admins == 0;
  }

  $c->db->query(
    'DELETE FROM project_members WHERE project_id = ? AND user_id = ?',
    $project_id, $user_id,
  );

  _audit($c, 'project.member.remove', $project_id,
    { user_id => 0 + $user_id, role => $existing->{role} },
    undef,
  );

  $c->render(json => { ok => 1 });
}

sub _err ($c, $status, $code) {
  $c->render(json => { error => $code }, status => $status);
  return undef;
}

sub _project ($c, $id) {
  return $c->db->query(
    'SELECT id, name, slug FROM projects WHERE id = ?',
    $id,
  )->hash;
}

sub _public_member ($m) {
  return {
    user_id   => 0 + $m->{user_id},
    email     => $m->{email},
    name      => $m->{name},
    role      => $m->{role},
    is_active => $m->{is_active} ? 1 : 0,
    added_at  => $m->{added_at},
  };
}

sub _audit ($c, $action, $project_id, $old, $new) {
  my $me = $c->current_user;
  $c->db->query(
    q{
      INSERT INTO audit_log (user_id, action, entity_type, entity_id, old_value, new_value, ip)
      VALUES (?, ?, 'project', ?, ?, ?, ?)
    },
    $me ? $me->{id} : undef,
    $action,
    $project_id,
    defined $old ? Mojo::JSON::encode_json($old) : undef,
    defined $new ? Mojo::JSON::encode_json($new) : undef,
    $c->tx->remote_address,
  );
}

1;
