package TMS;
use Mojo::Base 'Mojolicious', -signatures;

use Dotenv;

sub startup ($self) {
  # ------------------------------------------------------------
  # Load .env from the app home (absolute path, cwd-independent)
  # ------------------------------------------------------------
  my $env_file = $self->home->child('.env')->to_string;
  Dotenv->load($env_file) if -f $env_file;

  # ------------------------------------------------------------
  # App config
  # ------------------------------------------------------------
  $self->secrets([ $ENV{TMS_SECRET} // 'dev-only-change-me' ]);

  $self->{app_name}    = 'TMS';
  $self->{app_version} = '0.0.1';

  # ------------------------------------------------------------
  # Routes
  # ------------------------------------------------------------
  my $r = $self->routes;

  $r->get('/')->to(cb => sub ($c) {
    $c->render(json => {
      app     => $self->{app_name},
      version => $self->{app_version},
      docs    => '/api/v1/health',
    });
  });

  $r->get('/api/v1/health')->to(cb => sub ($c) {
    $c->render(json => {
      status  => 'ok',
      app     => $self->{app_name},
      version => $self->{app_version},
      time    => time,
    });
  });
}

1;
