package TMS;
use Mojo::Base 'Mojolicious', -signatures;

use Dotenv;

sub startup ($self) {
  my $env_file = $self->home->child('.env')->to_string;
  Dotenv->load($env_file) if -f $env_file;

  $self->secrets([ $ENV{TMS_SECRET} // 'dev-only-change-me' ]);

  $self->{app_name}    = 'TMS';
  $self->{app_version} = '0.0.1';

  $self->plugin('TMS::Plugin::DB');
  $self->plugin('TMS::Plugin::Auth');
  $self->plugin('TMS::Plugin::AI');
  $self->plugin('TMS::Routes::API');
}

1;
