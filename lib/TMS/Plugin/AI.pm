package TMS::Plugin::AI;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use TMS::Engine;

sub register ($self, $app, $conf) {
  my @engines = (
    {
      name    => 'libretranslate',
      label   => 'LibreTranslate',
      enabled => _truthy($ENV{LIBRETRANSLATE_URL}),
      config  => { url => $ENV{LIBRETRANSLATE_URL} },
    },
    {
      name    => 'gemini',
      label   => 'Gemini',
      enabled => _truthy($ENV{GEMINI_API_KEY}),
      config  => { api_key => $ENV{GEMINI_API_KEY} },
    },
  );

  for my $e (@engines) {
    next unless $e->{enabled};
    $app->log->info("AI engine enabled: $e->{label}");
  }

  my $ai = TMS::Plugin::AI::Runtime->new(engines => \@engines);

  $app->helper(ai => sub ($c) { $ai });

  $app->helper(ai_engines => sub ($c) {
    return [
      map {
        {
          name    => $_->{name},
          label   => $_->{label},
          enabled => $_->{enabled} ? 1 : 0,
        }
      } @{ $ai->engines }
    ];
  });

  $app->helper(ai_engine => sub ($c, $name) {
    return $ai->engine($name);
  });
}

sub _truthy ($v) {
  return defined $v && length $v ? 1 : 0;
}

1;

package TMS::Plugin::AI::Runtime;
use Mojo::Base -base, -signatures;

has 'engines';

sub engine ($self, $name) {
  die "AI: unsupported engine '$name'\n"
    unless defined $name && length $name;

  my ($meta) = grep { $_->{name} eq $name } @{ $self->engines };
  die "AI: unsupported engine '$name'\n" unless $meta;
  die "AI: engine '$name' is not configured\n" unless $meta->{enabled};

  return TMS::Engine->for($name, $meta->{config});
}

1;
