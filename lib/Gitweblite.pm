package Gitweblite;
use Mojo::Base 'Mojolicious';

use FindBin;
use lib "$FindBin::Bin/lib";
use File::Basename 'dirname';
use lib dirname(__FILE__) . '/lib';
use Fcntl ':mode';
use File::Basename 'basename';
use Carp 'croak';
use Validator::Custom;
use Encode qw/encode decode/;
use Gitweblite::Git;

our $VERSION = '0.01';

# Encode
sub e($) { encode('UTF-8', shift) }

has 'validator';
has 'git';

my @diff_opts = ('-M');
my $prevent_xss = 0;

sub startup {
  my $self = shift;
  
  my $conf = $self->plugin('Config');

  # Config
  my $projectroots = $conf->{projectroots};
  my $projectroot = $conf->{projectroots}->[0];
  my $projects_list = $conf->{projects_list} ||= $projectroot;

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
    $r = $r->waypoint('/')->via('get')->to('default#projectroots');
    
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
    $r->get('/blob_plain')->to('#blob');
    $r->get('/blobdiff(:suffix)')->to('#blobdiff', suffix => '');
    $r->get('/snapshot')->to('#snapshot');
  }
}

1;
