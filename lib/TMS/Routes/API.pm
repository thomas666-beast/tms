package TMS::Routes::API;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

sub register ($self, $app, $conf) {
  my $r = $app->routes;

  # ----------------------------------------------------------
  # public root + health
  # ----------------------------------------------------------
  $r->get('/')->to(cb => sub ($c) {
    $c->render(json => {
      app     => $app->{app_name},
      version => $app->{app_version},
      docs    => '/api/v1/health',
    });
  });

  $r->get('/api/v1/health')->to(cb => sub ($c) {
    my $db_status = 'ok';
    my $db_error;

    eval {
      my $row = $c->db->query('SELECT 1 AS ok')->hash;
      die 'unexpected result' unless $row && $row->{ok} == 1;
      1;
    } or do {
      $db_status = 'error';
      $db_error  = $@ || 'unknown error';
      chomp $db_error;
    };

    $c->render(json => {
      status  => 'ok',
      app     => $app->{app_name},
      version => $app->{app_version},
      db      => $db_status,
      (defined $db_error ? (db_error => $db_error) : ()),
      time    => time,
    });
  });

  # ----------------------------------------------------------
  # /api/v1 (all under here)
  # ----------------------------------------------------------
  my $api = $r->under('/api/v1');

  # public: login/logout/me
  $api->post('/auth/login')->to('Auth#login');
  $api->post('/auth/logout')->to('Auth#logout');
  $api->get ('/auth/me')  ->to('Auth#me');

  # ----------------------------------------------------------
  # admin-only: users
  # ----------------------------------------------------------
  my $admin = $api->under(sub ($c) {
    return $c->require_role('admin');
  });

  $admin->get  ('/users')             ->to('Users#list');
  $admin->post ('/users')             ->to('Users#create');
  $admin->patch('/users/:id')         ->to('Users#update');
  $admin->post ('/users/:id/password')->to('Users#set_password');
}

1;
