package TMS::Adapter;
use Mojo::Base -base, -signatures;

my %ADAPTERS = (
  laravel => 'TMS::Adapter::Laravel',
  vue     => 'TMS::Adapter::VueI18n',
);

sub for ($class, $name) {
  die "TMS::Adapter: unsupported format '$name'\n"
    unless defined $name && exists $ADAPTERS{$name};

  my $module = $ADAPTERS{$name};
  (my $path = "$module.pm") =~ s{::}{/}g;
  require $path;
  return $module->new;
}

sub known ($class) {
  return sort keys %ADAPTERS;
}

1;
