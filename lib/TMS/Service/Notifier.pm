package TMS::Service::Notifier;
use Mojo::Base -base, -signatures;

use Mojo::JSON;

has 'db';

sub emit ($self, $user_id, $type, $entity_type, $entity_id, $payload = {}) {
  return unless defined $user_id;

  # Check user preferences
  my $prefs = $self->db->query(
    'SELECT notification_preferences FROM users WHERE id = ?',
    $user_id,
  )->hash->{notification_preferences} // {};

  # Convert JSONB to Perl hash if needed
  if (!ref $prefs) {
    require Mojo::JSON;
    $prefs = eval { Mojo::JSON::decode_json($prefs) } || {};
  }

  # If the specific preference is explicitly set to 0, skip
  return if defined $prefs->{$type} && !$prefs->{$type};

  $self->db->query(
    q{
      INSERT INTO notifications
        (user_id, type, entity_type, entity_id, payload)
      VALUES (?, ?, ?, ?, ?::jsonb)
    },
    $user_id, $type, $entity_type, $entity_id, Mojo::JSON::encode_json($payload),
  );
}

sub emit_many ($self, $user_ids, $type, $entity_type, $entity_id, $payload = {}) {
  my %seen;
  for my $uid (@$user_ids) {
    next unless defined $uid;
    next if $seen{$uid}++;
    $self->emit($uid, $type, $entity_type, $entity_id, $payload);
  }
}

sub project_leads_and_admins ($self, $project_id, $exclude_user_id = undef) {
  my $rows = $self->db->query(
    q{
      SELECT user_id
        FROM project_members
       WHERE project_id = ?
         AND role IN ('admin','lead')
    },
    $project_id,
  )->arrays;

  my @ids = map { $_->[0] } @$rows;

  my $admins = $self->db->query(
    q{
      SELECT u.id
        FROM users u
        JOIN project_members m ON m.user_id = u.id AND m.project_id = ?
       WHERE u.role = 'admin' AND u.is_active
    },
    $project_id,
  )->arrays;
  push @ids, map { $_->[0] } @$admins;

  return [ grep { !defined $exclude_user_id || $_ != $exclude_user_id } @ids ];
}

sub project_admins ($self, $project_id, $exclude_user_id = undef) {
  my $rows = $self->db->query(
    q{
      SELECT user_id
        FROM project_members
       WHERE project_id = ?
         AND role = 'admin'
    },
    $project_id,
  )->arrays;

  my @ids = map { $_->[0] } @$rows;

  my $admins = $self->db->query(
    q{
      SELECT u.id
        FROM users u
        JOIN project_members m ON m.user_id = u.id AND m.project_id = ?
       WHERE u.role = 'admin' AND u.is_active
    },
    $project_id,
  )->arrays;
  push @ids, map { $_->[0] } @$admins;

  return [ grep { !defined $exclude_user_id || $_ != $exclude_user_id } @ids ];
}

1;
