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
      my ($self, $project) = @_;
      
      my $head_commit = $self->app->git->parse_commit($project, "HEAD");
      my $head_id = $head_commit->{id};
      
      return $head_id;
    });
  }

  # Route
  my $r = $self->routes;
  {
    my $r = $r->route->to('main#');
    
    # Home
    $r->get('/')->to('#home');
    
    # Project
    $r->get('/(*home)/projects')->to('#projects')->name('projects');
    
    # Summary
    my $project_re = qr/.+?\.git/;
    $r->get('/(*project)/summary', [project => $project_re])
      ->to('#summary')->name('summary');
    
    # Short log
    $r->get('/(*project)/shortlog/(*id)', [project => $project_re], {id => 'HEAD'})
      ->to('#shortlog')->name('shortlog');
    
    # Log
    $r->get('/(*project)/log/(*id)', [project => $project_re], {id => 'HEAD'})
      ->to('#log')->name('log');
    
    # Commit
    $r->get('/(*project)/commit/(*id)', [project => $project_re])
      ->to('#commit')->name('commit');
    
    # Commit diff
    $r->get('/(*project)/commitdiff/(*id)', [project => $project_re])
      ->to('#commitdiff')->name('commitdiff');

    # Tags
    $r->get('/(*project)/tags', [project => $project_re])
      ->to('#tags')->name('tags');
    
    # Tag
    $r->get('/(*project)/tag/(*id)', [project => $project_re])
      ->to('#tag')->name('tag');
    
    # Heads
    $r->get('/(*project)/heads', [project => $project_re])
      ->to('#heads')->name('heads');
    
    # Tree
    $r->get('/(*project)/tree/(*id_dir)', [project => $project_re], {id_dir => 'HEAD'})
      ->to('#tree')->name('tree');
    
    # Blob
    $r->get('/(*project)/blob/(*id_file)', [project => $project_re])
      ->to('#blob')->name('blob');
    
    # Blob plain
    $r->get('/(*project)/blob_plain/(*id_file)', [project => $project_re])
      ->to('#blob', plain => 1)->name('blob_plain');
    
    # Blob diff
    $r->get('/(*project)/blobdiff(:suffix)', [project => $project_re])
      ->to('#blobdiff', suffix => '')->name('blobdiff');
    
    # Snapshot
    $r->get('/(*project)/snapshot/(*id)', [project => $project_re])
      ->to('#snapshot')->name('snapshot');
  }
}

1;
