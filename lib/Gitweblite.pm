package Gitweblite;
use Mojo::Base 'Mojolicious';

use Validator::Custom;
use Gitweblite::Git;

our $VERSION = '0.03';

has 'validator';
has 'git';

sub startup {
  my $self = shift;
  
  # Config
  my $conf = {};
  if (-f $self->home->rel_file('gitweblite.conf')) {
    $conf = $self->plugin('JSONConfigLoose', {ext => 'conf'});
  }
  my $search_dirs = $conf->{search_dirs} || ['/git/pub', '/home'];
  $self->config(search_dirs => $search_dirs);
  my $search_max_depth = $conf->{search_max_depth} || 10;
  $self->config(search_max_depth => $search_max_depth);
  
  # Git
  my $git = Gitweblite::Git->new;
  my $git_bin = $conf->{git_bin} ? $conf->{git_bin} : $git->search_bin;
  die qq/Can't detect git command. set "git_bin" in gitweblite.conf/
    unless $git_bin;
  $git->bin($git_bin);
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
  
  # Added user public and templates path
  unshift @{$self->static->paths}, $self->home->rel_file('user/public');
  unshift @{$self->renderer->paths}, $self->home->rel_file('user/templates');

  # Route
  my $r = $self->routes->route->to('main#');
    
  # Home
  $r->get('/')->to('#home');
  
  # Projects
  $r->get('/(*home)/projects')->to('#projects')->name('projects');
  
  # Project
  {
    my $r = $r->route('/(*project)', project => qr/.+?\.git/);
    
    # Summary
    $r->get('/summary')->to('#summary')->name('summary');
    
    # Short log
    $r->get('/shortlog/(*id)', {id => 'HEAD'})
      ->to('#log', short => 1)->name('shortlog');
    
    # Log
    $r->get('/log/(*id)', {id => 'HEAD'})->to('#log')->name('log');
    
    # Commit
    $r->get('/commit/(*id)')->to('#commit')->name('commit');
    
    # Commit diff
    $r->get('/commitdiff/(*diff)')->to('#commitdiff')->name('commitdiff');
    
    # Commit diff plain
    $r->get('/commitdiff_plain/(*diff)')
      ->to('#commitdiff', plain => 1)->name('commitdiff_plain');
    
    # Tags
    $r->get('/tags')->to('#tags')->name('tags');
    
    # Tag
    $r->get('/tag/(*id)')->to('#tag')->name('tag');
    
    # Heads
    $r->get('/heads')->to('#heads')->name('heads');
    
    # Tree
    $r->get('/tree/(*id_dir)', {id_dir => 'HEAD'})
      ->to('#tree')->name('tree');
    
    # Blob
    $r->get('/blob/(*id_file)')->to('#blob')->name('blob');
    
    # Blob plain
    $r->get('/blob_plain/(*id_file)')
      ->to('#blob', plain => 1)->name('blob_plain');
    
    # Blob diff
    $r->get('/blobdiff/(#diff)/(*file)')
      ->to('#blobdiff')->name('blobdiff');

    # Blob diff plain
    $r->get('/blobdiff_plain/(#diff)/(*file)')
      ->to('#blobdiff', plain => 1)->name('blobdiff_plain');
    
    # Snapshot
    $r->get('/snapshot/(:id)', {id => 'HEAD'})->to('#snapshot')->name('snapshot');
  }
  
  # File cache
  my $dirs = $self->config('search_dirs');
  my $max_depth = $self->config('search_max_depth');
  $git->search_projects(
    dirs => $dirs,
    max_depth => $max_depth
  );
}

1;
