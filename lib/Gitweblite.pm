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
  
  # Helper
  {
    # Remove top slash
    $self->helper('gitweblite_rel' => sub {
      my ($self, $path) = @_;
      
      $path =~ s/^\///;
      
      return $path;
    });
    
    # Get head commit id
    $self->helper('gitweblite_get_head_id' => sub {
      my ($self, $home, $project) = @_;
      
      my $head_commit = $self->app->git->parse_commit($home, $project, "HEAD");
      my $head_cid = $head_commit->{id};
      
      return $head_cid;
    });
  }

  # Route
  my $r = $self->routes;
  {
    my $r = $r->route->to('main#');
    
    # Home
    $r->get('/')->to('#home');
    
    # Project
    $r->get('/(*home)/project')->to('#project')->name('project');
    
    # Summary
    $r->get('/(*home)/(.project)/summary')->to('#summary')->name('summary');
    
    # Short log
    $r->get('/(*home)/(.project)/shortlog')
      ->to('#shortlog')->name('shortlog');
    
    # Log
    $r->get('/(*home)/(.project)/log')->to('#log')->name('log');
    
    # Commit
    $r->get('/(*home)/(.project)/commit/:cid')->to('#commit')->name('commit');
    
    # Commit diff
    $r->get('/(*home)/(.project)/commitdiff/:cid')
      ->to('#commitdiff')->name('commitdiff');

    # Tags
    $r->get('/(*home)/(.project)/tags')->to('#tags')->name('tags');
    
    # Tag
    $r->get('/(*home)/(.project)/tag/:id')->to('#tag')->name('tag');
    
    # Heads
    $r->get('/(*home)/(.project)/heads')->to('#heads')->name('heads');
    
    # Tree
    $r->get('/(*home)/(.project)/tree/:cid(*dir)', [cid => qr/[0-9a-fA-F]{40}/])
      ->to('#tree')->name('tree');
    
    # Blob
    $r->get('/(*home)/(.project)/blob/:cid/(*file)', [cid => qr/[0-9a-fA-F]{40}/])
      ->to('#blob')->name('blob');
    $r->get('/(*home)/(.project)/blob/:bid')->to('#blob')->name('blob_bid');
    
    # Blob plain
    $r->get('/(*home)/(.project)/blob_plain/:cid/(*file)', [cid => qr/[0-9a-fA-F]{40}/])
      ->to('#blob_plain')->name('blob_plain');
    $r->get('/(*home)/(.project)/blob_plain/:bid')->to('#blob_plain')->name('blob_plain');
    
    # Blob diff
    $r->get('/(*home)/(.project)/blobdiff(:suffix)')
      ->to('#blobdiff', suffix => '')->name('blobdiff');
    
    # Snapshot
    $r->get('/(*home)/(.project)/snapshot/:cid')->to('#snapshot')->name('snapshot');
  }
}

1;
