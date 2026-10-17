#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

use FindBin;
use File::Find;
use File::Spec;
use File::Basename qw(dirname);
use File::Path qw(make_path);

my $root_dir = File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '..'));

my @files;
find(
  sub {
    return unless -f;
    return if $File::Find::dir =~ m{/\.git(/|$)};
    return if $File::Find::dir =~ m{/\.bak(/|$)};
    return if $File::Find::dir =~ m{/local(/|$)};
    push @files, $File::Find::name if /\.(pm|pl|t)$/;
  },
  map { File::Spec->catdir($root_dir, $_) } qw(lib script t),
);

if (!@files) {
  print "No Perl files found.\n";
  exit 0;
}

# 1. Copy each file to .bak/<relpath> before reformatting
for my $abs (@files) {
  (my $rel = $abs) =~ s{^\Q$root_dir\E/}{};
  my $bak = File::Spec->catfile($root_dir, '.bak', $rel);

  my $dir = dirname($bak);
  make_path($dir) unless -d $dir;

  system('cp', '-f', $abs, $bak) == 0
    or die "failed to copy $abs to $bak\n";
}

# 2. Run perltidy in place (no -b, so it doesn't create its own backups)
my @cmd = ('perltidy', @files);
print "Running: @cmd\n";

system(@cmd) == 0 or die "perltidy failed (exit $?)\n";

print "Formatted " . scalar(@files) . " file(s); backups in .bak/.\n";

exit 0;