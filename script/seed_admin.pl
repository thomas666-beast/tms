#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Dotenv;
Dotenv->load("$FindBin::Bin/../.env");

use Getopt::Long qw(GetOptions);
use Mojo::Pg;
use Authen::Passphrase::BlowfishCrypt;

# ------------------------------------------------------------
# CLI parsing
# ------------------------------------------------------------
my ( $email, $name, $password, $role, $db_url );
$role   = 'admin';
$db_url = $ENV{DATABASE_URL};

GetOptions(
  'email=s'    => \$email,
  'name=s'     => \$name,
  'password=s' => \$password,
  'role=s'     => \$role,
  'db=s'       => \$db_url,
) or usage();

usage() unless $email && $name && $password;

unless ( $role =~ /^(admin|lead_translator|translator)$/ ) {
  die "invalid --role '$role' (must be admin | lead_translator | translator)\n";
}

die "DATABASE_URL is not set (check .env or pass --db)\n"
  unless defined $db_url && length $db_url;

# ------------------------------------------------------------
# Hash password (bcrypt cost 10)
# ------------------------------------------------------------
my $crypted = Authen::Passphrase::BlowfishCrypt->new(
  cost        => 10,
  salt_random => 1,
  passphrase  => $password,
)->as_rfc2307;

# ------------------------------------------------------------
# Upsert
# ------------------------------------------------------------
my $pg = Mojo::Pg->new($db_url);

my $row = $pg->db->query(
  q{
    INSERT INTO users (email, name, password_hash, role, is_active)
    VALUES (?, ?, ?, ?, true)
    ON CONFLICT (email) DO UPDATE
      SET name          = EXCLUDED.name,
          password_hash = EXCLUDED.password_hash,
          role          = EXCLUDED.role,
          is_active     = true
    RETURNING id, (xmax = 0) AS inserted
  },
  $email, $name, $crypted, $role,
)->hash;

# audit
$pg->db->query(
  q{
    INSERT INTO audit_log (user_id, action, entity_type, entity_id, new_value)
    VALUES (NULL, 'user.seed', 'user', ?, ?::jsonb)
  },
  $row->{id},
  qq{{"email":"$email","role":"$role","inserted":$row->{inserted}}},
);

printf "%s user %s (id=%d, role=%s)\n",
  ( $row->{inserted} ? 'Created' : 'Updated' ),
  $email, $row->{id}, $role;

exit 0;

# ------------------------------------------------------------
sub usage {
  die <<'USAGE';
Usage:
  perl script/seed_admin.pl --email=EMAIL --name=NAME --password=PASS [--role=ROLE] [--db=URL]

  --role  admin (default) | lead_translator | translator
  --db    PostgreSQL URL; defaults to $DATABASE_URL

Re-running with the same email updates name, password, role and reactivates the user.
USAGE
}
