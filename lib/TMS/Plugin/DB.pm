package TMS::Plugin::DB;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Mojo::Pg;

sub register ($self, $app, $conf) {
  my $url = $ENV{DATABASE_URL};
  die "DATABASE_URL is not set\n" unless defined $url && length $url;

  my $pg = Mojo::Pg->new($url);
  $pg->max_connections(10);

  # app-level helpers (used by scripts, plugins, etc.)
  $app->helper(pg => sub ($c) { $pg });
  $app->helper(db => sub ($c) { $pg->db });

  # store the pool on the app object too, for `script/*` and `t/*.t`
  # that don't go through a controller
  $app->attr(pg_pool => sub { $pg });
}

1;
