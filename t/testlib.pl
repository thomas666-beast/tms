use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Dotenv;
Dotenv->load("$FindBin::Bin/../.env");

# Only override if not already set explicitly (allows CI to pin its own URL).
unless (defined $ENV{TMS_TEST_DATABASE_URL} && length $ENV{TMS_TEST_DATABASE_URL}) {
  my $base = $ENV{DATABASE_URL};
  die "DATABASE_URL is not set (check .env)\n" unless defined $base && length $base;

  (my $test = $base) =~ s{/([^/?]+)(\?|$)}{/tms_test$2};
  $ENV{TMS_TEST_DATABASE_URL} = $test;
}

$ENV{DATABASE_URL} = $ENV{TMS_TEST_DATABASE_URL};

die "refusing to run tests against a database whose name does not end in _test: $ENV{DATABASE_URL}\n"
  unless $ENV{DATABASE_URL} =~ m{/[^/?]+_test(\?|$)};

1;
