package TMS::Plugin::DB;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Mojo::Pg;
use TMS::Service::Notifier;

sub register ($self, $app, $conf) {
  my $url = $ENV{DATABASE_URL};
  die "DATABASE_URL is not set\n" unless defined $url && length $url;

  my $pg = Mojo::Pg->new($url);
  $pg->max_connections(10);

  $app->helper(pg => sub ($c) { $pg });

  # One connection per request: every $c->db call in the same request
  # reuses the same handle, so BEGIN/COMMIT and sequential reads/writes
  # all happen on the same connection. It returns to the pool when the
  # request (and its stash) is destroyed.
  $app->helper(db => sub ($c) { $c->stash->{'tms.db'} //= $pg->db });

  $app->helper(notifier => sub ($c) {
    TMS::Service::Notifier->new(db => $c->db);
  });

  $app->attr(pg_pool => sub { $pg });
}

1;
