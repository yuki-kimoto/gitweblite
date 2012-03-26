package Gitweblite;
use Mojo::Base 'Mojolicious';

use Validator::Custom;
use Gitweblite::Git;

our $VERSION = '0.01';

has 'validator';
has 'git';

sub startup {
  my $self = shift;
  
  # Config
  my $conf = $self->plugin('Config');
  my $projectroots = $conf->{projectroots};
  my $projectroot = $conf->{projectroots}->[0];

  # Git
  my $git_bin = $conf->{git} ? $conf->{git} : '/usr/local/bin/git';
  my $git = Gitweblite::Git->new(bin => $git_bin);
  $self->git($git);

  # Validator
  my $validator = Validator::Custom->new;
  $validator->register_constraint(hex => sub {
    my $value = shift;
    return 0 unless defined $value;
    $value =~ /^[0-9a-fA-F]+$/ ? 1 : 0;
  });
  $self->validator($validator);
  
  # Route
  {
    my $r = $self->routes;
    
    # Top
    $r = $r->waypoint('/')->via('get')->to('default#homes');
    
    # Others
    $r->get('/projects')->to('#projects');
    $r->get('/summary')->to('#summary');
    $r->get('/shortlog')->to('#shortlog');
    $r->get('/log')->to('#log');
    $r->get('/commit')->to('#commit');
    $r->get('/commitdiff(:suffix)')->to('#commitdiff', suffix => '');
    $r->get('/tag')->to('#tag');
    $r->get('/tags')->to('#tags');
    $r->get('head')->to('#head');
    $r->get('/heads')->to('#heads');
    $r->get('/tree')->to('#tree');
    $r->get('/blob')->to('#blob');
    $r->get('/blob_plain')->to('#blob_plain');
    $r->get('/blobdiff(:suffix)')->to('#blobdiff', suffix => '');
    $r->get('/snapshot')->to('#snapshot');
  }
}

1;
