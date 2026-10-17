package TMS::Plugin::Auth;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

sub register ($self, $app, $conf) {
  my $cookie_name = $conf->{cookie_name} // 'tms_session';

  # ----------------------------------------------------------
  # session cookie helpers
  # ----------------------------------------------------------
  $app->helper(session_cookie_name => sub ($c) { $cookie_name });

  $app->helper(set_session_cookie => sub ($c, $sid) {
    $c->cookie(
      $cookie_name => $sid => {
        path     => '/',
        httponly => 1,
        samesite => 'Lax',
        secure   => $app->mode eq 'production' ? 1 : 0,
        max_age  => 7 * 24 * 60 * 60,
      },
    );
  });

  $app->helper(clear_session_cookie => sub ($c) {
    $c->cookie(
      $cookie_name => '' => {
        path     => '/',
        httponly => 1,
        samesite => 'Lax',
        secure   => $app->mode eq 'production' ? 1 : 0,
        expires  => 1,
      },
    );
  });

  # ----------------------------------------------------------
  # current_user (lazy — loads from DB once per request)
  # ----------------------------------------------------------
  $app->helper(current_user => sub ($c) {
    return $c->stash('current_user') if exists $c->stash->{current_user};

    my $cookie = $c->req->cookie($cookie_name);
    my $sid    = $cookie ? $cookie->value : undef;

    unless (defined $sid && length $sid) {
      $c->stash(current_user => undef);
      return undef;
    }

    my $u = $c->db->query(
      q{
        SELECT u.id, u.email, u.name, u.role, u.is_active
          FROM sessions s
          JOIN users u ON u.id = s.user_id
         WHERE s.id = ?
           AND s.revoked_at IS NULL
           AND s.expires_at > now()
           AND u.is_active
      },
      $sid,
    )->hash;

    $c->stash(current_user => $u);
    return $u;
  });

  # ----------------------------------------------------------
  # require_auth (returns 401 if not logged in)
  # ----------------------------------------------------------
  $app->helper(require_auth => sub ($c) {
    return 1 if $c->current_user;
    $c->render(json => { error => 'unauthorized' }, status => 401);
    return undef;
  });

  # ----------------------------------------------------------
  # require_role (@roles) — returns 403 if wrong role
  # ----------------------------------------------------------
  $app->helper(require_role => sub ($c, @roles) {
    my $u = $c->current_user;
    return $c->render(json => { error => 'unauthorized' }, status => 401)
      unless $u;
    return 1 if grep { $_ eq $u->{role} } @roles;
    $c->render(json => { error => 'forbidden' }, status => 403);
    return undef;
  });
}

1;
