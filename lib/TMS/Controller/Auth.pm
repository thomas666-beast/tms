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

  my $sid = _new_session_id();
  $c->db->query(
    q{
      INSERT INTO sessions (id, user_id, ip, user_agent, expires_at)
      VALUES (?, ?, ?, ?, now() + interval '7 days')
    },
    $sid,
    $u->{id},
    $c->tx->remote_address,
    $c->req->headers->user_agent,
  );

  $c->set_session_cookie($sid);

  delete $u->{password_hash};

  $c->render(json => { user => _public_user($u) });
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
  $c->render(json => { user => _public_user($u) });
}

sub _public_user ($u) {
  return {
    id    => 0 + $u->{id},
    email => $u->{email},
    name  => $u->{name},
    role  => $u->{role},
  };
}

sub _new_session_id {
  my $hex = '';
  $hex .= sprintf '%02x', int rand 256 for 1 .. 32;
  return $hex;
}

1;
