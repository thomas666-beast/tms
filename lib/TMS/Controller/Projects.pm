package TMS::Controller::Projects;
use Mojo::Base 'Mojolicious::Controller', -signatures;

# ------------------------------------------------------------
# GET /api/v1/projects
# ------------------------------------------------------------
sub list ($c) {
  my $u = $c->current_user;

  my $rows = $u->{role} eq 'admin'
    ? $c->db->query(
        q{
          SELECT p.id, p.name, p.slug, p.default_source_lang,
                 p.created_at, p.updated_at
            FROM projects p
           ORDER BY p.created_at DESC, p.id DESC
        },
      )->hashes
    : $c->db->query(
        q{
          SELECT p.id, p.name, p.slug, p.default_source_lang,
                 p.created_at, p.updated_at, m.role AS member_role
            FROM projects p
            JOIN project_members m ON m.project_id = p.id AND m.user_id = ?
           ORDER BY p.created_at DESC, p.id DESC
        },
        $u->{id},
      )->hashes;

  $c->render(json => {
    projects => [ map { _public_project($_) } @$rows ],
  });
}

# ------------------------------------------------------------
# POST /api/v1/projects  { name, default_source_lang }
# ------------------------------------------------------------
sub create ($c) {
  my $body = $c->req->json || {};
  my $name = $body->{name}                // '';
  my $lang = $body->{default_source_lang} // '';

  return _err($c, 400, 'name_required') unless length $name;
  return _err($c, 400, 'default_source_lang_required') unless length $lang;

  my $u = $c->current_user;

  my $slug = _unique_slug($c, $name);

  my $project = $c->db->query(
    q{
      INSERT INTO projects (name, slug, default_source_lang, created_by)
      VALUES (?, ?, ?, ?)
      RETURNING id, name, slug, default_source_lang, created_at, updated_at
    },
    $name, $slug, $lang, $u->{id},
  )->hash;

  # creator becomes project admin
  $c->db->query(
    q{
      INSERT INTO project_members (project_id, user_id, role, added_by)
      VALUES (?, ?, 'admin', ?)
    },
    $project->{id}, $u->{id}, $u->{id},
  );

  _audit($c, 'project.create', $project->{id}, undef, {
    name                => $project->{name},
    slug                => $project->{slug},
    default_source_lang => $project->{default_source_lang},
  });

  $c->render(json => { project => _public_project($project) }, status => 201);
}

# ------------------------------------------------------------
# GET /api/v1/projects/:id
# ------------------------------------------------------------
sub show ($c) {
  my $id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $id =~ /\A\d+\z/;

  return undef unless $c->can_access_project($id);

  my $project = $c->db->query(
    q{
      SELECT id, name, slug, default_source_lang, created_at, updated_at
        FROM projects
       WHERE id = ?
    },
    $id,
  )->hash;

  return _err($c, 404, 'project_not_found') unless $project;

  # include members for the caller if they can see the project
  my $members = $c->db->query(
    q{
      SELECT m.user_id, m.role, u.email, u.name
        FROM project_members m
        JOIN users u ON u.id = m.user_id
       WHERE m.project_id = ?
       ORDER BY m.added_at, m.user_id
    },
    $id,
  )->hashes;

  $c->render(json => {
    project => _public_project($project),
    members => [ map { _public_member($_) } @$members ],
  });
}

# ------------------------------------------------------------
# PATCH /api/v1/projects/:id  { name?, default_source_lang? }
# ------------------------------------------------------------
sub update ($c) {
  my $id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $id =~ /\A\d+\z/;

  return undef unless $c->can_access_project($id);

  my $u = $c->current_user;
  my $member = $c->project_member($id);
  my $is_project_admin = $u->{role} eq 'admin'
    || ($member && $member->{role} eq 'admin');

  return _err($c, 403, 'forbidden') unless $is_project_admin;

  my $project = $c->db->query(
    'SELECT id, name, slug, default_source_lang FROM projects WHERE id = ?',
    $id,
  )->hash;
  return _err($c, 404, 'project_not_found') unless $project;

  my $body = $c->req->json || {};

  my @sets;
  my @args;

  if (exists $body->{name}) {
    my $name = $body->{name} // '';
    return _err($c, 400, 'name_required') unless length $name;
    push @sets, 'name = ?'; push @args, $name;
  }

  if (exists $body->{default_source_lang}) {
    my $lang = $body->{default_source_lang} // '';
    return _err($c, 400, 'default_source_lang_required') unless length $lang;
    push @sets, 'default_source_lang = ?'; push @args, $lang;
  }

  return _err($c, 400, 'nothing_to_update') unless @sets;

  push @args, $id;

  my $row = $c->db->query(
    'UPDATE projects SET ' . join(', ', @sets) . '
     WHERE id = ?
     RETURNING id, name, slug, default_source_lang, created_at, updated_at',
    @args,
  )->hash;

  _audit($c, 'project.update', $row->{id},
    { name => $project->{name}, default_source_lang => $project->{default_source_lang} },
    { name => $row->{name},     default_source_lang => $row->{default_source_lang} },
  );

  $c->render(json => { project => _public_project($row) });
}
# ------------------------------------------------------------
# helpers
# ------------------------------------------------------------
sub _err ($c, $status, $code) {
  $c->render(json => { error => $code }, status => $status);
  return undef;
}

sub _public_project ($p) {
  my %out = (
    id                  => 0 + $p->{id},
    name                => $p->{name},
    slug                => $p->{slug},
    default_source_lang => $p->{default_source_lang},
    created_at          => $p->{created_at},
    updated_at          => $p->{updated_at},
  );
  $out{member_role} = $p->{member_role} if defined $p->{member_role};
  return \%out;
}

sub _public_member ($m) {
  return {
    user_id => 0 + $m->{user_id},
    email   => $m->{email},
    name    => $m->{name},
    role    => $m->{role},
  };
}

sub _unique_slug ($c, $name) {
  (my $base = lc $name) =~ s/[^a-z0-9]+/-/g;
  $base =~ s/^-+//; $base =~ s/-+$//;
  $base = 'project' unless length $base;

  my $slug = $base;
  my $n    = 1;
  while ($c->db->query('SELECT 1 FROM projects WHERE slug = ?', $slug)->hash) {
    $n++;
    $slug = "$base-$n";
  }
  return $slug;
}

sub _audit ($c, $action, $entity_id, $old, $new) {
  my $me = $c->current_user;
  $c->db->query(
    q{
      INSERT INTO audit_log (user_id, action, entity_type, entity_id, old_value, new_value, ip)
      VALUES (?, ?, 'project', ?, ?, ?, ?)
    },
    $me ? $me->{id} : undef,
    $action,
    $entity_id,
    defined $old ? Mojo::JSON::encode_json($old) : undef,
    defined $new ? Mojo::JSON::encode_json($new) : undef,
    $c->tx->remote_address,
  );
}

1;
