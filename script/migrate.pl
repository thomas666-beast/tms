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
use Digest::SHA qw(sha256_hex);

# ------------------------------------------------------------
# CLI
# ------------------------------------------------------------
my ( $db_url, $sql_dir );
$db_url  = $ENV{DATABASE_URL};
$sql_dir = "$FindBin::Bin/../sql";

GetOptions(
  'db=s'      => \$db_url,
  'sql-dir=s' => \$sql_dir,
) or usage();

die "DATABASE_URL is not set (check .env or pass --db)\n"
  unless defined $db_url && length $db_url;

die "sql directory not found: $sql_dir\n" unless -d $sql_dir;

# ------------------------------------------------------------
# Connect
# ------------------------------------------------------------
my $pg = Mojo::Pg->new($db_url);
my $db = $pg->db;

# ------------------------------------------------------------
# Ensure schema_migrations exists (bootstrap)
# ------------------------------------------------------------
$db->query(<<'SQL');
CREATE TABLE IF NOT EXISTS schema_migrations (
  version    TEXT        PRIMARY KEY,
  checksum   TEXT        NOT NULL,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL

# ------------------------------------------------------------
# Load applied versions
# ------------------------------------------------------------
my %applied = map { $_->{version} => $_->{checksum} }
  @{ $db->query('SELECT version, checksum FROM schema_migrations')->hashes };

# ------------------------------------------------------------
# Discover files
# ------------------------------------------------------------
opendir my $dh, $sql_dir or die "cannot open $sql_dir: $!";
my @files = sort grep {/\.sql$/} readdir $dh;
closedir $dh;

die "no .sql files in $sql_dir\n" unless @files;

# ------------------------------------------------------------
# Apply
# ------------------------------------------------------------
my ( $applied_count, $skipped_count ) = ( 0, 0 );

for my $file (@files) {
  my $path = "$sql_dir/$file";

  open my $fh, '<', $path or die "cannot open $path: $!";
  my $content = do { local $/; <$fh> };
  close $fh;

  my $checksum = sha256_hex($content);

  if ( exists $applied{$file} ) {
    if ( $applied{$file} ne $checksum ) {
      die "migration $file was already applied but its content has changed.\n"
        . "Migrations are immutable. Add a new file instead of editing this one.\n";
    }
    $skipped_count++;
    next;
  }

  print "Applying $file … ";

  eval {
    $db->query('BEGIN');
    $db->query($content);
    $db->query( 'INSERT INTO schema_migrations (version, checksum) VALUES (?, ?)',
      $file, $checksum, );
    $db->query('COMMIT');
    1;
  } or do {
    my $err = $@;
    eval { $db->query('ROLLBACK') };
    die "failed to apply $file: $err\n";
  };

  print "ok\n";
  $applied_count++;
}

print $applied_count
  ? "Applied $applied_count migration(s). ($skipped_count already applied.)\n"
  : "Nothing to do. ($skipped_count migrations already applied.)\n";

exit 0;

sub usage {
  die <<'USAGE';
Usage:
  perl script/migrate.pl [--db=URL] [--sql-dir=PATH]

  --db       PostgreSQL URL; defaults to $DATABASE_URL
  --sql-dir  Directory containing .sql files; defaults to ../sql
USAGE
}
