package TMS::Routes::API;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

sub register ($self, $app, $conf) {
  my $r = $app->routes;

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

  my $api = $r->under('/api/v1');

  $api->post('/auth/login')->to('Auth#login');
  $api->post('/auth/logout')->to('Auth#logout');
  $api->get ('/auth/me')  ->to('Auth#me');

  my $authed = $api->under(sub ($c) {
    return $c->require_auth;
  });

  $authed->get  ('/projects')                      ->to('Projects#list');
  $authed->get  ('/projects/:id')                  ->to('Projects#show');
  $authed->patch('/projects/:id')                  ->to('Projects#update');

  $authed->get  ('/projects/:id/members')          ->to('ProjectMembers#list');
  $authed->post ('/projects/:id/members')          ->to('ProjectMembers#add');
  $authed->patch('/projects/:id/members/:user_id') ->to('ProjectMembers#update');
  $authed->delete  ('/projects/:id/members/:user_id') ->to('ProjectMembers#remove');

  $authed->post ('/projects/:id/files')            ->to('Files#upload');

  my $admin = $api->under(sub ($c) {
    return $c->require_role('admin');
  });

  $admin->post ('/projects')          ->to('Projects#create');
  $admin->get  ('/users')             ->to('Users#list');
  $admin->post ('/users')             ->to('Users#create');
  $admin->patch('/users/:id')         ->to('Users#update');
  $admin->post ('/users/:id/password')->to('Users#set_password');
}

1;
