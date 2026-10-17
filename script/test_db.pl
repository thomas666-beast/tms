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

my ($base_url, $test_db);
$base_url = $ENV{DATABASE_URL};
$test_db  = 'tms_test';

GetOptions(
  'db=s'       => \$base_url,
  'test-db=s'  => \$test_db,
) or usage();

die "DATABASE_URL is not set (check .env or pass --db)\n"
  unless defined $base_url && length $base_url;

die "test database name must end in _test (got: $test_db)\n"
  unless $test_db =~ /_test\z/;

# derive admin URL (maintenance DB = "postgres")
my $admin_uri = URI->new($base_url);
$admin_uri->path('/postgres');
my $admin_url = $admin_uri->as_string;

# derive test URL (same host/user/pass, db = $test_db)
my $test_uri = URI->new($base_url);
$test_uri->path("/$test_db");
my $test_url = $test_uri->as_string;

print "Resetting test database '$test_db' ...\n";

{
  my $db = Mojo::Pg->new($admin_url)->db;
  $db->query(qq{DROP DATABASE IF EXISTS "$test_db" WITH (FORCE)});
  $db->query(qq{CREATE DATABASE "$test_db"});
}

print "  recreated\n";

print "Applying migrations to $test_db ...\n";
system(
  $^X, "$FindBin::Bin/migrate.pl",
  '--db' => $test_url,
) == 0 or die "migrate.pl failed\n";

my $email    = $ENV{TMS_DEV_ADMIN_EMAIL}    // 'admin@example.com';
my $name     = $ENV{TMS_DEV_ADMIN_NAME}     // 'Root Admin';
my $password = $ENV{TMS_DEV_ADMIN_PASSWORD};

die "TMS_DEV_ADMIN_PASSWORD is not set in .env\n"
  unless defined $password && length $password;

print "Seeding admin $email into $test_db ...\n";
system(
  $^X, "$FindBin::Bin/seed_admin.pl",
  '--db'       => $test_url,
  '--email'    => $email,
  '--name'     => $name,
  '--password' => $password,
) == 0 or die "seed_admin.pl failed\n";

print "Done. Run tests with:  carton exec -- prove -l t\n";

exit 0;

sub usage {
  die <<'USAGE';
Usage:
  perl script/test_db.pl [--db=URL] [--test-db=NAME]

  --db       Base PostgreSQL URL (default: $DATABASE_URL); the test DB
             is derived by replacing the database name
  --test-db  Test database name (default: tms_test); must end in _test
USAGE
}
