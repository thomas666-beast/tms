package TMS::Controller::Files;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use TMS::Adapter;

sub upload ($c) {
  my $project_id = $c->param('id');
  return _err($c, 400, 'invalid_id') unless $project_id =~ /\A\d+\z/;

  return undef unless $c->can_access_project($project_id);

  my $me = $c->current_user;
  my $member = $c->project_member($project_id);
  my $is_project_admin = $me->{role} eq 'admin'
    || ($member && $member->{role} eq 'admin');
  return _err($c, 403, 'forbidden') unless $is_project_admin;

  my $project = $c->db->query(
    'SELECT id FROM projects WHERE id = ?',
    $project_id,
  )->hash;
  return _err($c, 404, 'project_not_found') unless $project;

  my $format      = $c->param('format')      // '';
  my $source_lang = $c->param('source_lang') // '';
  my $target_lang = $c->param('target_lang') // '';
  my $name        = $c->param('name');
  my $group_id    = $c->param('group_id');

  return _err($c, 400, 'format_required')      unless length $format;
  return _err($c, 400, 'source_lang_required') unless length $source_lang;
  return _err($c, 400, 'target_lang_required') unless length $target_lang;

  return _err($c, 400, 'invalid_lang')
    unless $source_lang =~ /\A[A-Za-z][A-Za-z0-9_-]{0,19}\z/
        && $target_lang =~ /\A[A-Za-z][A-Za-z0-9_-]{0,19}\z/;

  my $adapter = eval { TMS::Adapter->for($format) };
  return _err($c, 400, 'unsupported_format') unless $adapter;

  my $upload = $c->req->upload('file');
  return _err($c, 400, 'file_required') unless $upload;

  if (!$upload->size) {
    return _err($c, 400, 'file_empty');
  }

  $name = $upload->filename unless defined $name && length $name;
  return _err($c, 400, 'name_required') unless defined $name && length $name;

  if (defined $group_id) {
    return _err($c, 400, 'invalid_group_id') unless $group_id =~ /\A\d+\z/;
    my $g = $c->db->query(
      'SELECT 1 FROM file_groups WHERE id = ? AND project_id = ?',
      $group_id, $project_id,
    )->hash;
    return _err($c, 404, 'group_not_found') unless $g;
  }

  my $existing = $c->db->query(
    'SELECT 1 FROM files WHERE project_id = ? AND name = ? AND target_lang = ?',
    $project_id, $name, $target_lang,
  )->hash;
  return _err($c, 409, 'file_exists') if $existing;

  my $content = $upload->slurp;
  my $parsed  = eval { $adapter->parse($content) };
  if (!$parsed) {
    my $msg = $@ || 'parse failed';
    chomp $msg;
    return _err($c, 400, 'invalid_file', { detail => $msg });
  }

  my $file;
  eval {
    $c->db->query('BEGIN');

    $file = $c->db->query(
      q{
        INSERT INTO files
          (project_id, group_id, name, format, source_lang, target_lang,
           is_source, status, created_by)
        VALUES (?, ?, ?, ?, ?, ?, false, 'in_progress', ?)
        RETURNING id, project_id, name, format, source_lang, target_lang, status, created_at
      },
      $project_id, $group_id, $name, $format, $source_lang, $target_lang, $me->{id},
    )->hash;

    my $revision = $c->db->query(
      q{
        INSERT INTO file_revisions (file_id, revision_number, status, created_by_user_id)
        VALUES (?, 1, 'open', ?)
        RETURNING id, revision_number, status, created_at
      },
      $file->{id}, $me->{id},
    )->hash;

    $c->db->query(
      'UPDATE files SET current_revision_id = ? WHERE id = ?',
      $revision->{id}, $file->{id},
    );

    for my $key_path (sort keys %$parsed) {
      $c->db->query(
        q{
          INSERT INTO keys (file_id, key_path, source_text)
          VALUES (?, ?, ?)
        },
        $file->{id}, $key_path, $parsed->{$key_path},
      );
    }

    $c->db->query('COMMIT');
    1;
  } or do {
    my $err = $@;
    eval { $c->db->query('ROLLBACK') };
    return _err($c, 500, 'file_create_failed', { detail => "$err" });
  };

  _audit($c, 'file.create', $file->{id}, {
    project_id  => 0 + $project_id,
    name        => $file->{name},
    format      => $file->{format},
    source_lang => $file->{source_lang},
    target_lang => $file->{target_lang},
  });

  $c->render(json => {
    file => {
      id          => 0 + $file->{id},
      project_id  => 0 + $file->{project_id},
      name        => $file->{name},
      format      => $file->{format},
      source_lang => $file->{source_lang},
      target_lang => $file->{target_lang},
      status      => $file->{status},
      keys_count  => scalar(keys %$parsed),
      created_at  => $file->{created_at},
    },
  }, status => 201);
}

sub _err ($c, $status, $code, $extra = undef) {
  my %payload = (error => $code);
  $payload{detail} = $extra->{detail} if $extra && defined $extra->{detail};
  $c->render(json => \%payload, status => $status);
  return undef;
}

sub _audit ($c, $action, $entity_id, $new) {
  my $me = $c->current_user;
  $c->db->query(
    q{
      INSERT INTO audit_log (user_id, action, entity_type, entity_id, new_value, ip)
      VALUES (?, ?, 'file', ?, ?, ?)
    },
    $me ? $me->{id} : undef,
    $action,
    $entity_id,
    defined $new ? Mojo::JSON::encode_json($new) : undef,
    $c->tx->remote_address,
  );
}

1;
