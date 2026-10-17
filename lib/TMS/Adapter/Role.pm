package TMS::Adapter::Role;
use Mojo::Base -role;

requires qw(name extension parse serialize);

1;
