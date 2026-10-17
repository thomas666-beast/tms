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
use URI;
use URI::QueryParam;

# ------------------------------------------------------------
# CLI
# ------------------------------------------------------------
my ( $db_url, $admin_url, $email, $name, $password, $skip_seed );
$db_url   = $ENV{DATABASE_URL};
$email    = $ENV{TMS_DEV_ADMIN_EMAIL} // 'admin@example.com';
$name     = $ENV{TMS_DEV_ADMIN_NAME}  // 'Root Admin';
$password = $ENV{TMS_DEV_ADMIN_PASSWORD};

GetOptions(
  'db=s'             => \$db_url,
  'admin-db=s'       => \$admin_url,
  'admin-email=s'    => \$email,
  'admin-name=s'     => \$name,
  'admin-password=s' => \$password,
  'skip-seed'        => \$skip_seed,
) or usage();

die "DATABASE_URL is not set (check .env or pass --db)\n"
  unless defined $db_url && length $db_url;

die "admin password is not set (set TMS_DEV_ADMIN_PASSWORD in .env, "
  . "or pass --admin-password)\n"
  unless $skip_seed || ( defined $password && length $password );

# ------------------------------------------------------------
# Derive admin URL if not passed: swap db name to `postgres`
# ------------------------------------------------------------
unless ( defined $admin_url && length $admin_url ) {
  my $uri = URI->new($db_url);
  $uri->path('/postgres');
  $admin_url = $uri->as_string;
}

# ------------------------------------------------------------
# Parse DB name from DATABASE_URL
# ------------------------------------------------------------
my $uri     = URI->new($db_url);
my $db_name = ( $uri->path_segments )[-1] // '';
die "could not parse database name from DATABASE_URL\n" unless length $db_name;

die "refusing to reset the maintenance database 'postgres'\n"
  if $db_name eq 'postgres';

# ------------------------------------------------------------
# Refuse to run if not in development
# ------------------------------------------------------------
my $app_mode = $ENV{TMS_MODE} // 'development';
die "reset_db.pl refuses to run outside development (TMS_MODE=$app_mode)\n"
  unless $app_mode eq 'development';

print "Resetting database '$db_name' ...\n";

# ------------------------------------------------------------
# Drop and recreate
# ------------------------------------------------------------
{
  my $db = Mojo::Pg->new($admin_url)->db;

  $db->query(qq{DROP DATABASE IF EXISTS "$db_name" WITH (FORCE)});
  $db->query(qq{CREATE DATABASE "$db_name"});
}

print "  recreated\n";

# ------------------------------------------------------------
# Apply migrations
# ------------------------------------------------------------
print "Applying migrations …\n";
system( $^X, "$FindBin::Bin/migrate.pl", '--db' => $db_url, ) == 0 or die "migrate.pl failed\n";

# ------------------------------------------------------------
# Seed admin
# ------------------------------------------------------------
if ($skip_seed) {
  print "Skipping admin seed (--skip-seed).\n";
}
else {
  print "Seeding admin $email …\n";
  system(
    $^X, "$FindBin::Bin/seed_admin.pl",
    '--db'       => $db_url,
    '--email'    => $email,
    '--name'     => $name,
    '--password' => $password,
  ) == 0 or die "seed_admin.pl failed\n";
}

print "Done.\n";

exit 0;

sub usage {
  die <<'USAGE';
Usage:
  perl script/reset_db.pl [options]

  --db=URL               PostgreSQL URL (default: $DATABASE_URL)
  --admin-db=URL         Maintenance DB URL (default: DATABASE_URL with db=postgres)
  --admin-email=EMAIL    Dev admin email (default: $TMS_DEV_ADMIN_EMAIL)
  --admin-name=NAME      Dev admin name  (default: $TMS_DEV_ADMIN_NAME)
  --admin-password=PASS  Dev admin password (default: $TMS_DEV_ADMIN_PASSWORD)
  --skip-seed            Don't seed an admin

Requires TMS_MODE=development (or unset).
USAGE
}
