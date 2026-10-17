package TMS::Controller::Me;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub dashboard ($c) {
  my $me = $c->current_user;

  my $assigned = $c->db->query(
    q{
      SELECT f.id, f.name, f.format, f.status, f.target_lang, f.source_lang,
             f.updated_at,
             p.id   AS project_id,
             p.name AS project_name
        FROM files f
        JOIN projects p ON p.id = f.project_id
       WHERE f.assigned_to_user_id = ?
         AND f.status IN ('assigned','in_progress','in_review')
       ORDER BY f.updated_at DESC
       LIMIT 10
    },
    $me->{id},
  )->hashes;

  my $reviewable = $c->db->query(
    q{
      SELECT DISTINCT f.id, f.name, f.status, f.target_lang, f.updated_at,
             p.id   AS project_id,
             p.name AS project_name,
             (SELECT count(*) FROM approvals a
                WHERE a.revision_id = f.current_revision_id
                  AND a.decision = 'approve') AS approval_count
        FROM files f
        JOIN projects p ON p.id = f.project_id
        LEFT JOIN project_members m ON m.project_id = f.project_id AND m.user_id = ?
       WHERE f.status = 'in_review'
         AND (
              ? = 'admin'
              OR m.role IN ('admin','lead')
         )
       ORDER BY f.updated_at DESC
       LIMIT 10
    },
    $me->{id}, $me->{role},
  )->hashes;

  my $approved = $c->db->query(
    q{
      SELECT DISTINCT f.id, f.name, f.status, f.target_lang, f.updated_at,
             p.id   AS project_id,
             p.name AS project_name
        FROM files f
        JOIN projects p ON p.id = f.project_id
        LEFT JOIN approvals a
          ON a.file_id = f.id AND a.user_id = ?
       WHERE f.status = 'approved'
         AND (f.assigned_to_user_id = ? OR a.id IS NOT NULL)
       ORDER BY f.updated_at DESC
       LIMIT 10
    },
    $me->{id}, $me->{id},
  )->hashes;

  $c->render(json => {
    assigned        => [ map { _row($_) } @$assigned ],
    reviewable      => [ map { _row($_) } @$reviewable ],
    recent_approved => [ map { _row($_) } @$approved ],
  });
}

sub _row ($r) {
  my %out = (
    id           => 0 + $r->{id},
    name         => $r->{name},
    status       => $r->{status},
    target_lang  => $r->{target_lang},
    project_id   => 0 + $r->{project_id},
    project_name => $r->{project_name},
  );
  $out{approval_count} = 0 + $r->{approval_count} if exists $r->{approval_count};
  return \%out;
}

1;
