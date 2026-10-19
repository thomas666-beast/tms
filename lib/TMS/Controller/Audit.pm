package TMS::Controller::Audit;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub project ($c) {
  my $project_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless defined $project_id && $project_id =~ /\A\d+\z/;

  return undef unless $c->can_access_project($project_id);

  my $page = $c->param('page') // 1;
  my $per_page = $c->param('per_page') // 50;
  $page = 1 unless $page =~ /\A\d+\z/ && $page >= 1;
  $per_page = 50 unless $per_page =~ /\A\d+\z/ && $per_page >= 1;
  $per_page = 100 if $per_page > 100;

  # We only show events for the project itself, its files, and its keys
  my $total = $c->db->query(
    q{
      SELECT count(*) AS n
        FROM audit_log a
        LEFT JOIN users u ON u.id = a.user_id
        LEFT JOIN files f ON a.entity_type = 'file' AND a.entity_id = f.id
        LEFT JOIN keys k ON a.entity_type = 'key' AND a.entity_id = k.id
        LEFT JOIN files f2 ON k.file_id = f2.id
       WHERE (a.entity_type = 'project' AND a.entity_id = ?)
          OR (a.entity_type = 'file' AND f.project_id = ?)
          OR (a.entity_type = 'key' AND f2.project_id = ?)
    },
    $project_id, $project_id, $project_id,
  )->hash->{n};

  my $offset = ($page - 1) * $per_page;

  my $rows = $c->db->query(
    q{
      SELECT a.id, a.action, a.entity_type, a.entity_id, a.new_value, a.created_at,
             u.name AS user_name
        FROM audit_log a
        LEFT JOIN users u ON u.id = a.user_id
        LEFT JOIN files f ON a.entity_type = 'file' AND a.entity_id = f.id
        LEFT JOIN keys k ON a.entity_type = 'key' AND a.entity_id = k.id
        LEFT JOIN files f2 ON k.file_id = f2.id
       WHERE (a.entity_type = 'project' AND a.entity_id = ?)
          OR (a.entity_type = 'file' AND f.project_id = ?)
          OR (a.entity_type = 'key' AND f2.project_id = ?)
       ORDER BY a.created_at DESC, a.id DESC
       LIMIT ? OFFSET ?
    },
    $project_id, $project_id, $project_id,
    $per_page, $offset,
  )->hashes;

  $c->render(json => {
    total      => 0 + $total,
    page       => 0 + $page,
    per_page   => 0 + $per_page,
    total_pages => $total ? int(($total + $per_page - 1) / $per_page) : 0,
    events     => [ map { _public_event($_) } @$rows ],
  });
}

sub _public_event ($r) {
  return {
    id          => 0 + $r->{id},
    action      => $r->{action},
    entity_type => $r->{entity_type},
    entity_id   => 0 + $r->{entity_id},
    user_name   => $r->{user_name} // 'System',
    created_at  => $r->{created_at},
    payload     => $r->{new_value},
  };
}

sub _err ($c, $status, $code) {
  $c->render(json => { error => $code }, status => $status);
  return undef;
}

1;
