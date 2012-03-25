package Gitweblite::Git;
use Mojo::Base -base;

use Carp 'croak';
use Encode qw/encode decode/;
use Gitweblite::Git;

sub e($) { encode('UTF-8', shift) }

has 'bin';

my $conf = {};
my $export_ok = $conf->{export_ok} || '';
my $export_auth_hook = $conf->{export_ok} || undef;

sub check_export_ok {
  my ($self, $dir) = @_;
  return ($self->check_head_link($dir) &&
    (!$export_ok || -e "$dir/$export_ok") &&
    (!$export_auth_hook || $export_auth_hook->($dir)));
}

sub check_head_link {
  my ($self, $dir) = @_;
  my $headfile = "$dir/HEAD";
  return ((-e $headfile) ||
    (-l $headfile && readlink($headfile) =~ /^refs\/heads\//));
}

sub get_project_owner {
  my ($self, $root, $project) = @_;
  
  my $git_dir = "$root/$project";
  my $user_id = (stat $git_dir)[4];
  my $user = getpwuid($user_id);
  
  return $user;
}

sub get_projects {
  my ($self, $root, %opt) = @_;
  my $filter = $opt{filter};
  
  opendir my $dh, e$root
    or croak qq/Can't open directory $root: $!/;
  
  my @projects;
  while (my $project = readdir $dh) {
    next unless $project =~ /\.git$/;
    next unless $self->check_export_ok("$root/$project");
    next if defined $filter && $project !~ /\Q$filter\E/;
    push @projects, { path => $project };
  }

  return @projects;
}

1;
