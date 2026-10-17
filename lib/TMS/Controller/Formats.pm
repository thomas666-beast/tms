package TMS::Controller::Formats;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub list ($c) {
  my $rows = $c->db->query(
    'SELECT code, label, file_ext FROM formats WHERE is_active ORDER BY label',
  )->hashes;

  $c->render(json => {
    formats => [ map {
      {
        code     => $_->{code},
        label    => $_->{label},
        file_ext => $_->{file_ext},
      }
    } @$rows ],
  });
}

1;
