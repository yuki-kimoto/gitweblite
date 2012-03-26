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

sub get_heads {
  my ($self, $root, $project, $limit, @classes) = @_;
  @classes = ('heads') unless @classes;
  my @patterns = map { "refs/$_" } @classes;
  my @heads;

  open my $fd, '-|', $self->git($root, $project), 'for-each-ref',
    ($limit ? '--count='.($limit+1) : ()), '--sort=-committerdate',
    '--format=%(objectname) %(refname) %(subject)%00%(committer)',
    @patterns
    or return;
  while (my $line = <$fd>) {
    my %ref_item;

    chomp $line;
    my ($refinfo, $committerinfo) = split(/\0/, $line);
    my ($cid, $name, $title) = split(' ', $refinfo, 3);
    my ($committer, $epoch, $tz) =
      ($committerinfo =~ /^(.*) ([0-9]+) (.*)$/);
    $ref_item{'fullname'}  = $name;
    $name =~ s!^refs/(?:head|remote)s/!!;

    $ref_item{'name'}  = $name;
    $ref_item{'id'}    = $cid;
    $ref_item{'title'} = $title || '(no commit message)';
    $ref_item{'epoch'} = $epoch;
    if ($epoch) {
      $ref_item{'age'} = $self->_age_string(time - $ref_item{'epoch'});
    } else {
      $ref_item{'age'} = "unknown";
    }

    push @heads, \%ref_item;
  }
  close $fd;

  return \@heads;
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

sub get_project_description {
  my ($self, $root, $project) = @_;
  
  my $git_dir = "$root/$project";
  my $description_file = "$git_dir/description";
  
  my $description = $self->_slurp($description_file) || '';
  
  return $description;
}

sub get_project_owner {
  my ($self, $root, $project) = @_;
  
  my $git_dir = "$root/$project";
  my $user_id = (stat $git_dir)[4];
  my $user = getpwuid($user_id);
  
  return $user;
}

sub get_tags {
  my ($self, $root, $project, $limit) = @_;
  my @tags;

  open my $fd, '-|', $self->git($root, $project), 'for-each-ref',
    ($limit ? '--count='.($limit+1) : ()), '--sort=-creatordate',
    '--format=%(objectname) %(objecttype) %(refname) '.
    '%(*objectname) %(*objecttype) %(subject)%00%(creator)',
    'refs/tags'
    or return;
  while (my $line = <$fd>) {
    my %ref_item;

    chomp $line;
    my ($refinfo, $creatorinfo) = split(/\0/, $line);
    my ($id, $type, $name, $refid, $reftype, $title) = split(' ', $refinfo, 6);
    my ($creator, $epoch, $tz) =
      ($creatorinfo =~ /^(.*) ([0-9]+) (.*)$/);
    $ref_item{'fullname'} = $name;
    $name =~ s!^refs/tags/!!;

    $ref_item{'type'} = $type;
    $ref_item{'id'} = $id;
    $ref_item{'name'} = $name;
    if ($type eq "tag") {
      $ref_item{'subject'} = $title;
      $ref_item{'reftype'} = $reftype;
      $ref_item{'refid'}   = $refid;
    } else {
      $ref_item{'reftype'} = $type;
      $ref_item{'refid'}   = $id;
    }

    if ($type eq "tag" || $type eq "commit") {
      $ref_item{'epoch'} = $epoch;
      if ($epoch) {
        $ref_item{'age'} = $self->_age_string(time - $ref_item{'epoch'});
      } else {
        $ref_item{'age'} = "unknown";
      }
    }

    push @tags, \%ref_item;
  }
  close $fd;

  return \@tags;
}

sub git {
  my ($self, $root, $project) = @_;
  my $git_dir = "$root/$project";
  
  return ($self->bin, "--git-dir=$git_dir");
}

sub _age_string {
  my ($self, $age) = @_;
  my $age_str;

  if ($age > 60*60*24*365*2) {
    $age_str = (int $age/60/60/24/365);
    $age_str .= " years ago";
  } elsif ($age > 60*60*24*(365/12)*2) {
    $age_str = int $age/60/60/24/(365/12);
    $age_str .= " months ago";
  } elsif ($age > 60*60*24*7*2) {
    $age_str = int $age/60/60/24/7;
    $age_str .= " weeks ago";
  } elsif ($age > 60*60*24*2) {
    $age_str = int $age/60/60/24;
    $age_str .= " days ago";
  } elsif ($age > 60*60*2) {
    $age_str = int $age/60/60;
    $age_str .= " hours ago";
  } elsif ($age > 60*2) {
    $age_str = int $age/60;
    $age_str .= " min ago";
  } elsif ($age > 2) {
    $age_str = int $age;
    $age_str .= " sec ago";
  } else {
    $age_str .= " right now";
  }
  return $age_str;
}

sub _slurp {
  my ($self, $file) = @_;
  
  open my $fh, '<', $file
    or die qq/Can't open file "$file": $!/;
  my $content = do { local $/; <$fh> };
  
  return $content;
}

1;
