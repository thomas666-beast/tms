use Mojo::Base -strict;
use Test::More;
use Test::Mojo;
use Mojo::Home;

use FindBin;
use lib "$FindBin::Bin/../lib";
use TMS;

my $t = Test::Mojo->new('TMS');

# Force the app home to repo root so `.env` and other files are found
$t->app->home( Mojo::Home->new("$FindBin::Bin/..") );

$t->get_ok('/')
  ->status_is(200)
  ->json_is('/app', 'TMS');

$t->get_ok('/api/v1/health')
  ->status_is(200)
  ->json_is('/status', 'ok')
  ->json_has('/version')
  ->json_has('/time');

done_testing;
