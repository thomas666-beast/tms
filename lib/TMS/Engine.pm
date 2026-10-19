package TMS::Engine;
use Mojo::Base -base, -signatures;

my %REGISTRY = (
  libretranslate => 'TMS::Engine::LibreTranslate',
  gemini         => 'TMS::Engine::Gemini',
);

our $FOR_TEST;

sub for ($class, $name, $config = undef) {
  die "TMS::Engine: unsupported engine '$name'\n"
    unless defined $name && exists $REGISTRY{$name};

  if ($FOR_TEST) {
    my $fake = $FOR_TEST->($name, $config);
    return $fake if $fake;
  }

  my $module = $REGISTRY{$name};
  (my $path = "$module.pm") =~ s{::}{/}g;
  require $path;

  my %args;
  if ($name eq 'libretranslate') {
    $args{url} = $config && defined $config->{url}
      ? $config->{url}
      : $ENV{LIBRETRANSLATE_URL};
    $args{ua} = $config->{ua} if $config && $config->{ua};
  }
  elsif ($name eq 'gemini') {
    $args{api_key} = $config && defined $config->{api_key}
      ? $config->{api_key}
      : $ENV{GEMINI_API_KEY};
    $args{ua} = $config->{ua} if $config && $config->{ua};
  }

  return $module->new(%args);
}

sub known ($class) { sort keys %REGISTRY }

1;
