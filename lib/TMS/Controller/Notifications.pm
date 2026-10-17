package TMS::Controller::Notifications;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::JSON qw(decode_json);

sub list ($c) {
  my $me = $c->current_user;
  my $only_unread = ($c->param('unread') // '') eq '1';

  my $sql = 'SELECT id, type, entity_type, entity_id, payload, read_at, created_at
               FROM notifications
              WHERE user_id = ?';
  $sql .= ' AND read_at IS NULL' if $only_unread;
  $sql .= ' ORDER BY id DESC LIMIT 100';

  my $rows = $c->db->query($sql, $me->{id})->hashes;

  my $unread = $c->db->query(
    'SELECT count(*) AS n FROM notifications WHERE user_id = ? AND read_at IS NULL',
    $me->{id},
  )->hash->{n};

  $c->render(json => {
    notifications => [ map { _public($_) } @$rows ],
    unread_count  => 0 + $unread,
  });
}

sub mark_read ($c) {
  my $id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless defined $id && $id =~ /\A\d+\z/;

  my $me = $c->current_user;
  my $row = $c->db->query(
    'SELECT id FROM notifications WHERE id = ? AND user_id = ?',
    $id, $me->{id},
  )->hash;
  return _err($c, 404, 'notification_not_found') unless $row;

  $c->db->query(
    'UPDATE notifications SET read_at = now() WHERE id = ? AND read_at IS NULL',
    $id,
  );

  $c->render(json => { ok => 1 });
}

sub mark_all_read ($c) {
  my $me = $c->current_user;
  my $updated = $c->db->query(
    'UPDATE notifications SET read_at = now() WHERE user_id = ? AND read_at IS NULL',
    $me->{id},
  )->rows;
  $c->render(json => { ok => 1, updated => 0 + $updated });
}

sub _err ($c, $status, $code) {
  $c->render(json => { error => $code }, status => $status);
  return undef;
}

sub _public ($r) {
  my $payload = $r->{payload};
  if (defined $payload && !ref $payload) {
    my $decoded = eval { decode_json($payload) };
    $payload = $decoded if $decoded;
  }
  return {
    id          => 0 + $r->{id},
    type        => $r->{type},
    entity_type => $r->{entity_type},
    entity_id   => 0 + $r->{entity_id},
    payload     => $payload || {},
    read_at     => $r->{read_at},
    created_at  => $r->{created_at},
  };
}

1;
