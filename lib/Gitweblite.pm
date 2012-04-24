package Gitweblite;
use Mojo::Base 'Mojolicious';

use Validator::Custom;
use Gitweblite::Git;
use File::Find 'find';
use File::Basename qw/basename dirname/;

our $VERSION = '0.01';

has 'validator';
has 'git';
has 'projects';

sub _search_projects {
  my ($self, %opt) = @_;
  my $dirs = $opt{dirs};
  my $max_depth = $opt{max_depth};
  
  # Git
  my $git = $self->git;
  
  # Search
  my @projects;
  for my $dir (@$dirs) {
    next unless -d $dir;
  
    $dir =~ s/\/$//;
    my $prefix_length = length($dir);
    my $prefix_depth = 0;
    for my $c (split //, $dir) {
      $prefix_depth++ if $c eq '/';
    }
    
    no warnings 'File::Find';
    File::Find::find({
      follow_fast => 1,
      follow_skip => 2,
      dangling_symlinks => 0,
      wanted => sub {
        my $path = $File::Find::name;
        my $base_path = $_;
        
        return if (m!^[/.]$!);
        return unless -d $base_path;
        
        if ($base_path eq '.git') {
          $File::Find::prune = 1;
          return;
        };
        
        my $depth = 0;
        for my $c (split //, $dir) {
          $depth++ if $c eq '/';
        }
        
        if ($depth - $prefix_depth > $max_depth) {
          $File::Find::prune = 1;
          return;
        }
        
        if (-d $path) {
          
          if ($git->check_head_link($path)) {
            my $home = dirname $path;
            my $name = basename $path;
            push @projects, {home => $home, name => $name};
            $File::Find::prune = 1;
          }
        }
      },
    }, $dir);
  }
  
  return \@projects;
}

sub startup {
  my $self = shift;
  
  # Config
  my $conf = $self->plugin('Config');
  my $search_dirs = $conf->{search_dirs} || ['/git/pub', '/home'];
  $self->config(search_dirs => $search_dirs);
  my $search_max_depth = $conf->{search_max_depth} || 10;
  $self->config(search_max_depth => $search_max_depth);
  
  # Git
  my $git_bin = $conf->{git_bin} ? $conf->{git_bin} : '/usr/local/bin/git';
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
  my $r = $self->routes;
  {
    my $r = $r->route->to('main#');
    $r->get('/')->to('#homes');
    $r->get('/projects')->to('#projects');
    $r->get('/summary')->to('#summary');
    $r->get('/shortlog')->to('#shortlog');
    $r->get('/log')->to('#log');
    $r->get('/commit')->to('#commit');
    $r->get('/commitdiff(:suffix)')->to('#commitdiff', suffix => '');
    $r->get('/tag')->to('#tag');
    $r->get('/tags')->to('#tags');
    $r->get('/heads')->to('#heads');
    $r->get('/tree')->to('#tree');
    $r->get('/blob')->to('#blob');
    $r->get('/blob_plain')->to('#blob_plain');
    $r->get('/blobdiff(:suffix)')->to('#blobdiff', suffix => '');
    $r->get('/snapshot')->to('#snapshot');
  }
}

1;
