package TMS::Controller::Users;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Authen::Passphrase::BlowfishCrypt;

# ------------------------------------------------------------
# GET /api/v1/users
# ------------------------------------------------------------
sub list ($c) {
  my $rows = $c->db->query(
    q{
      SELECT id, email, name, role, is_active,
             created_at, updated_at
        FROM users
       ORDER BY id
    },
  )->hashes;

  $c->render(json => { users => [ map { _public_row($_) } @$rows ] });
}

# ------------------------------------------------------------
# POST /api/v1/users  { email, name, password, role }
# ------------------------------------------------------------
sub create ($c) {
  my $body     = $c->req->json || {};
  my $email    = $body->{email}    // '';
  my $name     = $body->{name}     // '';
  my $password = $body->{password} // '';
  my $role     = $body->{role}     // 'translator';

  return _err($c, 400, 'email_required')    unless length $email;
  return _err($c, 400, 'name_required')     unless length $name;
  return _err($c, 400, 'password_required') unless length $password;
  return _err($c, 400, 'invalid_role')
    unless $role =~ /\A(?:admin|lead_translator|translator)\z/;

  my $exists = $c->db->query(
    'SELECT 1 FROM users WHERE email = ?',
    $email,
  )->hash;
  return _err($c, 409, 'email_taken') if $exists;

  my $hash = Authen::Passphrase::BlowfishCrypt->new(
    cost        => 10,
    salt_random => 1,
    passphrase  => $password,
  )->as_rfc2307;

  my $admin = $c->current_user;

  my $row = $c->db->query(
    q{
      INSERT INTO users (email, name, password_hash, role, is_active, created_by)
      VALUES (?, ?, ?, ?, true, ?)
      RETURNING id, email, name, role, is_active, created_at, updated_at
    },
    $email, $name, $hash, $role, $admin->{id},
  )->hash;

  _audit($c, 'user.create', $row->{id}, undef, _audit_payload($row));

  $c->render(json => { user => _public_row($row) }, status => 201);
}

# ------------------------------------------------------------
# PATCH /api/v1/users/:id  { name?, role?, is_active? }
# ------------------------------------------------------------
sub update ($c) {
  my $id   = $c->param('id');
  my $body = $c->req->json || {};

  return _err($c, 400, 'invalid_id') unless $id =~ /\A\d+\z/;

  my $user = $c->db->query(
    'SELECT id, email, name, role, is_active FROM users WHERE id = ?',
    $id,
  )->hash;
  return _err($c, 404, 'user_not_found') unless $user;

  my $me = $c->current_user;

  my ($new_name, $new_role, $new_active);
  $new_name = $body->{name} if exists $body->{name};
  $new_role = $body->{role} if exists $body->{role};

  if (exists $body->{is_active}) {
    my $v = $body->{is_active};
    return _err($c, 400, 'invalid_is_active') unless defined $v;
    $new_active = $v ? 1 : 0;
  }

  return _err($c, 400, 'name_required')
    if defined $new_name && !length $new_name;

  return _err($c, 400, 'invalid_role')
    if defined $new_role && $new_role !~ /\A(?:admin|lead_translator|translator)\z/;

  if (defined $new_active && !$new_active && $id == $me->{id}) {
    return _err($c, 409, 'cannot_deactivate_self');
  }

  if (defined $new_role && $user->{role} eq 'admin' && $new_role ne 'admin') {
    my $other_admins = $c->db->query(
      q{SELECT count(*) AS n FROM users WHERE role = 'admin' AND is_active AND id <> ?},
      $id,
    )->hash->{n};

    return _err($c, 409, 'last_admin') if $other_admins == 0;
  }

  my @sets;
  my @args;
  if (defined $new_name)   { push @sets, 'name = ?';      push @args, $new_name }
  if (defined $new_role)   { push @sets, 'role = ?';      push @args, $new_role }
  if (defined $new_active) { push @sets, 'is_active = ?'; push @args, $new_active }

  return _err($c, 400, 'nothing_to_update') unless @sets;

  push @args, $id;

  my $row = $c->db->query(
    'UPDATE users SET ' . join(', ', @sets) . '
     WHERE id = ?
     RETURNING id, email, name, role, is_active, created_at, updated_at',
    @args,
  )->hash;

  _audit($c, 'user.update', $row->{id}, _audit_payload($user), _audit_payload($row));

  $c->render(json => { user => _public_row($row) });
}

# ------------------------------------------------------------
# POST /api/v1/users/:id/password  { password }
# ------------------------------------------------------------
sub set_password ($c) {
  my $id   = $c->param('id');
  my $body = $c->req->json || {};
  my $new_password = $body->{password} // '';

  return _err($c, 400, 'invalid_id') unless $id =~ /\A\d+\z/;
  return _err($c, 400, 'password_required') unless length $new_password;

  my $user = $c->db->query(
    'SELECT id, email FROM users WHERE id = ?',
    $id,
  )->hash;
  return _err($c, 404, 'user_not_found') unless $user;

  my $hash = Authen::Passphrase::BlowfishCrypt->new(
    cost        => 10,
    salt_random => 1,
    passphrase  => $new_password,
  )->as_rfc2307;

  $c->db->query(
    'UPDATE users SET password_hash = ? WHERE id = ?',
    $hash, $id,
  );

  # revoke all active sessions for that user
  $c->db->query(
    'UPDATE sessions SET revoked_at = now() WHERE user_id = ? AND revoked_at IS NULL',
    $id,
  );

  _audit($c, 'user.set_password', $user->{id}, undef, { email => $user->{email} });

  $c->render(json => { ok => 1 });
}

# ------------------------------------------------------------
# helpers
# ------------------------------------------------------------
sub _err ($c, $status, $code) {
  $c->render(json => { error => $code }, status => $status);
  return undef;
}

sub _public_row ($r) {
  return {
    id         => 0 + $r->{id},
    email      => $r->{email},
    name       => $r->{name},
    role       => $r->{role},
    is_active  => $r->{is_active} ? 1 : 0,
    created_at => $r->{created_at},
    updated_at => $r->{updated_at},
  };
}

sub _audit_payload ($r) {
  return {
    email     => $r->{email},
    name      => $r->{name},
    role      => $r->{role},
    is_active => $r->{is_active} ? 1 : 0,
  };
}

sub _audit ($c, $action, $entity_id, $old, $new) {
  my $me = $c->current_user;
  $c->db->query(
    q{
      INSERT INTO audit_log (user_id, action, entity_type, entity_id, old_value, new_value, ip)
      VALUES (?, ?, 'user', ?, ?, ?, ?)
    },
    $me ? $me->{id} : undef,
    $action,
    $entity_id,
    defined $old ? Mojo::JSON::encode_json($old) : undef,
    defined $new ? Mojo::JSON::encode_json($new) : undef,
    $c->tx->remote_address,
  );
}

1;
