package TMS::Controller::Auth;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Authen::Passphrase::BlowfishCrypt;

sub login ($c) {
  my $body     = $c->req->json || {};
  my $email    = $body->{email}    // '';
  my $password = $body->{password} // '';

  return $c->render(json => { error => 'invalid_credentials' }, status => 401)
    unless length $email && length $password;

  my $u = $c->db->query(
    'SELECT id, email, name, password_hash, role, is_active
       FROM users
      WHERE email = ?',
    $email,
  )->hash;

  return $c->render(json => { error => 'invalid_credentials' }, status => 401)
    unless $u && $u->{is_active};

  my $ok = eval {
    my $pp = Authen::Passphrase::BlowfishCrypt->from_rfc2307($u->{password_hash});
    $pp->match($password) ? 1 : 0;
  } || 0;

  return $c->render(json => { error => 'invalid_credentials' }, status => 401)
    unless $ok;

  # rotate: drop the previous session, if any
  if (my $old = $c->req->cookie($c->session_cookie_name)) {
    $c->db->query(
      'DELETE FROM sessions WHERE id = ?',
      $old->value,
    );
  }

  # opportunistic cleanup of stale sessions
  $c->db->query(
    q{
      DELETE FROM sessions
       WHERE expires_at < now() - interval '7 days'
          OR (revoked_at IS NOT NULL AND revoked_at < now() - interval '7 days')
    },
  );

  my $sid        = _new_token();
  my $csrf_token = _new_token();

  $c->db->query(
    q{
      INSERT INTO sessions (id, user_id, ip, user_agent, csrf_token, expires_at)
      VALUES (?, ?, ?, ?, ?, now() + interval '7 days')
    },
    $sid,
    $u->{id},
    $c->tx->remote_address,
    $c->req->headers->user_agent,
    $csrf_token,
  );

  $c->set_session_cookie($sid);

  delete $u->{password_hash};

  $c->render(json => {
    user       => _public_user($u),
    csrf_token => $csrf_token,
  });
}

sub logout ($c) {
  my $cookie = $c->req->cookie($c->session_cookie_name);
  my $sid    = $cookie ? $cookie->value : undef;

  if (defined $sid && length $sid) {
    $c->db->query(
      'UPDATE sessions SET revoked_at = now() WHERE id = ? AND revoked_at IS NULL',
      $sid,
    );
  }

  $c->clear_session_cookie;
  $c->render(json => { ok => 1 });
}

sub me ($c) {
  my $u = $c->current_user;
  return $c->render(json => { user => undef }) unless $u;

  my $sid = $c->stash('session_id');
  my $csrf = defined $sid
    ? $c->db->query('SELECT csrf_token FROM sessions WHERE id = ?', $sid)->hash->{csrf_token}
    : undef;

  $c->render(json => {
    user       => _public_user($u),
    csrf_token => $csrf,
  });
}

sub _public_user ($u) {
  return {
    id    => 0 + $u->{id},
    email => $u->{email},
    name  => $u->{name},
    role  => $u->{role},
  };
}

sub _new_token {
  my $hex = '';
  $hex .= sprintf '%02x', int rand 256 for 1 .. 32;
  return $hex;
}

1;
