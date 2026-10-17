package TMS::Engine;
use Mojo::Base -base, -signatures;

my %REGISTRY = (
  libretranslate => 'TMS::Engine::LibreTranslate',
  gemini         => 'TMS::Engine::Gemini',
);

our $FOR_TEST;

sub for ($class, $name, $opts = undef) {
  die "TMS::Engine: unsupported engine '$name'\n"
    unless defined $name && exists $REGISTRY{$name};

  if ($FOR_TEST) {
    my $fake = $FOR_TEST->($name, $opts);
    return $fake if $fake;
  }

  my $module = $REGISTRY{$name};
  (my $path = "$module.pm") =~ s{::}{/}g;
  require $path;

  my %args;
  if ($name eq 'libretranslate') {
    $args{url} = $ENV{LIBRETRANSLATE_URL};
    $args{ua}  = $opts->{ua} if $opts && $opts->{ua};
  }
  elsif ($name eq 'gemini') {
    $args{api_key} = $ENV{GEMINI_API_KEY};
    $args{ua}      = $opts->{ua} if $opts && $opts->{ua};
  }

  return $module->new(%args);
}

sub known ($class) { sort keys %REGISTRY }

1;
