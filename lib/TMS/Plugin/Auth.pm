package TMS::Plugin::Auth;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Mojo::Util qw(secure_compare);

sub register ($self, $app, $conf) {
  my $cookie_name = $conf->{cookie_name} // 'tms_session';

  $app->helper(session_cookie_name => sub ($c) { $cookie_name });

  $app->helper(set_session_cookie => sub ($c, $sid) {
    $c->cookie(
      $cookie_name => $sid => {
        path     => '/',
        httponly => 1,
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
        secure   => $app->mode eq 'production' ? 1 : 0,
        expires  => 1,
      },
    );
  });

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

  $app->helper(project_member => sub ($c, $project_id) {
    my $u = $c->current_user or return undef;
    return $c->db->query(
      'SELECT role FROM project_members WHERE project_id = ? AND user_id = ?',
      $project_id, $u->{id},
    )->hash;
  });

  $app->helper(can_access_project => sub ($c, $project_id) {
    my $u = $c->current_user;
    return $c->render(json => { error => 'unauthorized' }, status => 401)
      unless $u;

    return 1 if $u->{role} eq 'admin';

    my $member = $c->project_member($project_id);
    return 1 if $member;

    $c->render(json => { error => 'forbidden' }, status => 403);
    return undef;
  });

  $app->hook(before_dispatch => sub ($c) {
    my $method = $c->req->method;
    return if $method eq 'GET' || $method eq 'HEAD' || $method eq 'OPTIONS';

    my $path = $c->req->url->path;
    return unless $path =~ m{^/api/v1/};

    return if $method eq 'POST' && $path eq '/api/v1/auth/login';

    my $cookie = $c->req->cookie($cookie_name);
    return unless $cookie && defined $cookie->value && length $cookie->value;

    my $sid = $cookie->value;

    my $row = $c->db->query(
      'SELECT csrf_token FROM sessions WHERE id = ?',
      $sid,
    )->hash;

    my $expected = $row ? $row->{csrf_token} : undef;
    my $got      = $c->req->headers->header('X-CSRF-Token') // '';

    return $c->render(json => { error => 'csrf_invalid' }, status => 403)
      unless defined $expected && length $expected && length $got
          && secure_compare($expected, $got);
  });
}

1;
