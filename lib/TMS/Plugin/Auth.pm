package TMS::Plugin::Auth;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

sub register ($self, $app, $conf) {
  my $cookie_name = $conf->{cookie_name} // 'tms_session';

  # ----------------------------------------------------------
  # cookie helpers
  # ----------------------------------------------------------
  $app->helper(session_cookie_name => sub ($c) { $cookie_name });

  $app->helper(set_session_cookie => sub ($c, $sid) {
    $c->cookie(
      $cookie_name => $sid => {
        path     => '/',
        httponly => 1,
        samesite => 'Strict',
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
        samesite => 'Strict',
        secure   => $app->mode eq 'production' ? 1 : 0,
        expires  => 1,
      },
    );
  });

  # ----------------------------------------------------------
  # current_user — loads from DB once per request
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

    $c->stash(session_id   => $sid);
    $c->stash(current_user => $u);
    return $u;
  });

  # ----------------------------------------------------------
  # require_auth / require_role
  # ----------------------------------------------------------
  $app->helper(require_auth => sub ($c) {
    return 1 if $c->current_user;
    $c->render(json => { error => 'unauthorized' }, status => 401);
    return undef;
  });

  $app->helper(require_role => sub ($c, @roles) {
    my $u = $c->current_user;
    return $c->render(json => { error => 'unauthorized' }, status => 401)
      unless $u;
    return 1 if grep { $_ eq $u->{role} } @roles;
    $c->render(json => { error => 'forbidden' }, status => 403);
    return undef;
  });

  # ----------------------------------------------------------
  # CSRF enforcement on unsafe methods
  # ----------------------------------------------------------
  $app->hook(before_dispatch => sub ($c) {
    my $method = $c->req->method;
    return if $method eq 'GET' || $method eq 'HEAD' || $method eq 'OPTIONS';

    # only protect /api/v1/* ; static files / future HTML routes are unaffected
    return unless $c->req->url->path =~ m{^/api/v1/};

    my $u = $c->current_user;
    return unless $u;   # unauthenticated requests are not CSRF-protected (login/logout are public)

    my $sid = $c->stash('session_id');
    return $c->render(json => { error => 'csrf_missing_session' }, status => 403)
      unless defined $sid;

    my $row = $c->db->query(
      'SELECT csrf_token FROM sessions WHERE id = ?',
      $sid,
    )->hash;

    my $expected = $row ? $row->{csrf_token} : undef;
    my $got      = $c->req->headers->header('X-CSRF-Token') // '';

    return $c->render(json => { error => 'csrf_invalid' }, status => 403)
      unless defined $expected && length $expected && $expected eq $got;
  });
}

1;
