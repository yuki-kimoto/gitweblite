package Gitweblite::Git;
use Mojo::Base -base;

use Carp 'croak';
use Encode qw/encode decode/;
use File::Find 'find';
use File::Basename qw/basename dirname/;
use Fcntl ':mode';
use constant {
  S_IFINVALID => 0030000,
  S_IFGITLINK => 0160000,
};

sub e($) { encode('UTF-8', shift) }
sub d($) { decode('UTF-8', shift) }

has 'bin';

my $conf = {};
my @diff_opts = ('-M');

sub search_bin {
  my $self = shift;
  
  my $env_path = $ENV{PATH};
  my @paths = split /:/, $env_path;
  
  for my $path (@paths) {
    $path =~ s#/$##;
    my $bin = "$path/git";
    if (-f $bin) {
      return $bin;
      last;
    }
  }
  return;
}

sub blob_mimetype {
  my ($self, $fh, $file) = @_;

  # just in case
  return 'text/plain' unless $fh;

  if (-T $fh) {
    return 'text/plain';
  } elsif (! $file) {
    return 'application/octet-stream';
  } elsif ($file =~ m/\.png$/i) {
    return 'image/png';
  } elsif ($file =~ m/\.gif$/i) {
    return 'image/gif';
  } elsif ($file =~ m/\.jpe?g$/i) {
    return 'image/jpeg';
  } else {
    return 'application/octet-stream';
  }
}

sub blob_contenttype {
  my ($self, $fh, $file, $type) = @_;

  $type ||= $self->blob_mimetype($fh, $file);
  if ($type eq 'text/plain') {
    $type .= "; charset=UTF-8";
  }

  return $type;
}

sub check_head_link {
  my ($self, $dir) = @_;
  my $headfile = "$dir/HEAD";
  return ((-e $headfile) ||
    (-l $headfile && readlink($headfile) =~ /^refs\/heads\//));
}

sub fill_from_file_info {
  my ($self, $project, $diff, $parents) = @_;

  $diff->{'from_file'} = [];
  $diff->{'from_file'}[$diff->{'nparents'} - 1] = undef;
  for (my $i = 0; $i < $diff->{'nparents'}; $i++) {
    if ($diff->{'status'}[$i] eq 'R' ||
        $diff->{'status'}[$i] eq 'C') {
      $diff->{'from_file'}[$i] =
        $self->get_path_by_id($project, $parents->[$i], $diff->{'from_id'}[$i]);
    }
  }

  return $diff;
}

sub get_path_by_id {
  my $self = shift;
  my $project = shift;
  my $base = shift || return;
  my $hash = shift || return;


  open my $fh, "-|", $self->cmd($project), "ls-tree", '-r', '-t', '-z', $base
    or return undef;

  local $/ = "\0";
  while (my $line = <$fh>) {
    $line = d$line;
    chomp $line;

    if ($line =~ m/(?:[0-9]+) (?:.+) $hash\t(.+)$/) {
      close $fh;
      return $1;
    }
  }
  close $fh;
  return undef;
}

sub is_deleted {
  my ($self, $diffinfo) = @_;

  return $diffinfo->{'to_id'} eq ('0' x 40);
}

sub fill_projects {
  my ($self, $home, $ps) = @_;

  my @projects;
  for my $project (@$ps) {
    my (@activity) = $self->get_last_activity("$home/$project->{path}");
    next unless @activity;
    ($project->{'age'}, $project->{'age_string'}) = @activity;
    if (!defined $project->{'descr'}) {
      my $descr = $self->get_project_description("$home/$project->{path}") || "";
      $project->{'descr_long'} = $descr;
      $project->{'descr'} = $self->_chop_str($descr, 25, 5);
    }

    push @projects, $project;
  }

  return @projects;
}

sub get_difftree {
  my ($self, $project, $cid, $parent, $parents) = @_;
  
  $parent = "--root" unless defined $parent;

  # Execute "git diff-tree"
  my @git_diff_tree = (
    $self->cmd($project),
    "diff-tree", '-r',
    "--no-commit-id",
    @diff_opts,
    (@$parents <= 1 ? $parent : '-c'),
    $cid,
    "--"
  );
  
  open my $fh, "-|", @git_diff_tree
    or die 500, "Open git-diff-tree failed";
  my @difftree = map { chomp; d$_ } <$fh>;
  close $fh or die "Reading git-diff-tree failed";
  
  # Parse "git diff-tree" output
  my $diffs = [];
  my @parents = @$parents;
  
  for my $line (@difftree) {
    my $diff = $self->parsed_difftree_line($line);

    if (exists $diff->{'nparents'}) {

      $self->fill_from_file_info($project, $diff, $parents)
        unless exists $diff->{'from_file'};

      $diff->{is_deleted} = 1 if $self->is_deleted($diff);
      push @$diffs, $diff;
    }
    else {
      my ($to_mode_oct, $to_mode_str, $to_file_type);
      my ($from_mode_oct, $from_mode_str, $from_file_type);
      if ($diff->{'to_mode'} ne ('0' x 6)) {
        $to_mode_oct = oct $diff->{'to_mode'};
        if (S_ISREG($to_mode_oct)) { # only for regular file
          $to_mode_str = sprintf("%04o", $to_mode_oct & 0777); # permission bits
        }
        $to_file_type = $self->file_type($diff->{'to_mode'});
      }
      if ($diff->{'from_mode'} ne ('0' x 6)) {
        $from_mode_oct = oct $diff->{'from_mode'};
        if (S_ISREG($from_mode_oct)) { # only for regular file
          $from_mode_str = sprintf("%04o", $from_mode_oct & 0777); # permission bits
        }
        $from_file_type = $self->file_type($diff->{'from_mode'});
      }
      
      $diff->{to_mode_str} = $to_mode_str;
      $diff->{to_mode_oct} = $to_mode_oct;
      $diff->{to_file_type} = $to_file_type;
      $diff->{from_mode_str} = $from_mode_str;
      $diff->{from_mode_oct} = $from_mode_oct;
      $diff->{from_file_type} = $from_file_type;

      push @$diffs, $diff;
    }
  }
  
  return $diffs;
}

sub get_head_id {
  my ($self, $project) = (shift, shift, shift);
  return get_id($project, 'HEAD', @_);
};

sub get_short_id {
  my ($self, $project) = (shift, shift, shift);
  return $self->get_id($project, @_, '--short=7');
}

sub get_id {
  my ($self, $project, $ref, @options) = @_;
  
  my $id;
  if (open my $fh, '-|', $self->cmd($project), 'rev-parse',
      '--verify', '-q', @options, $ref) {
    $id = <$fh>;
    $id = d$id;
    chomp $id if defined $id;
    close $fh;
  }
  return $id;
}

sub get_object_type {
  my ($self, $project, $cid) = @_;

  open my $fh, "-|", $self->cmd($project), "cat-file", '-t', $cid or return;
  my $type = <$fh>;
  $type = d$type;
  close $fh or return;
  chomp $type;
  return $type;
}

sub get_references {
  my ($self, $project, $type) = @_;
  $type ||= '';
  my %refs;
  open my $fh, "-|", $self->cmd($project), "show-ref", "--dereference",
    ($type ? ("--", "refs/$type") : ())
    or return;

  while (my $line = <$fh>) {
    $line = d$line;
    chomp $line;
    if ($line =~ m!^([0-9a-fA-F]{40})\srefs/($type.*)$!) {
      if (defined $refs{$1}) {
        push @{$refs{$1}}, $2;
      } else {
        $refs{$1} = [ $2 ];
      }
    }
  }
  close $fh or return;
  return \%refs;
}

sub id_set_multi {
  my ($self, $cid, $key, $value) = @_;

  if (!exists $cid->{$key}) {
    $cid->{$key} = $value;
  } elsif (!ref $cid->{$key}) {
    $cid->{$key} = [ $cid->{$key}, $value ];
  } else {
    push @{$cid->{$key}}, $value;
  }
}

sub get_id_by_path {
  my ($self, $project, $id, $path, $type) = @_;

  $path =~ s,/+$,,;
  
  my @git_ls_tree = (
    $self->cmd($project), "ls-tree", $id, "--", $path
  );
  
  open my $fh, "-|", @git_ls_tree
    or die "Open git-ls-tree failed";
  my $line = <$fh>;
  $line = d$line;
  close $fh or return undef;

  if (!defined $line) {
    # there is no tree or hash given by $path at $base
    return undef;
  }

  $line =~ m/^([0-9]+) (.+) ([0-9a-fA-F]{40})\t/;
  if (defined $type && $type ne $2) {
    # type doesn't match
    return undef;
  }
  return $3;
}

sub get_heads {
  my ($self, $project, $limit, @classes) = @_;
  @classes = ('heads') unless @classes;
  my @patterns = map { "refs/$_" } @classes;
  my @heads;

  open my $fh, '-|', $self->cmd($project), 'for-each-ref',
    ($limit ? '--count='.($limit+1) : ()), '--sort=-committerdate',
    '--format=%(objectname) %(refname) %(subject)%00%(committer)',
    @patterns
    or return;
  while (my $line = <$fh>) {
    $line = d$line;
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
  close $fh;

  return \@heads;
}

sub get_last_activity {
  my ($self, $project) = @_;

  my $fh;
  my @git_command = (
    $self->cmd($project),
    'for-each-ref',
    '--format=%(committer)',
    '--sort=-committerdate',
    '--count=1',
    'refs/heads'  
  );
  open($fh, "-|", @git_command) or return;
  my $most_recent = <$fh>;
  $most_recent = d$most_recent;
  
  close $fh or return;
  if (defined $most_recent &&
      $most_recent =~ / (\d+) [-+][01]\d\d\d$/) {
    my $timestamp = $1;
    my $age = time - $timestamp;
    return ($age, $self->_age_string($age));
  }
  return (undef, undef);
}

sub get_project_description {
  my ($self, $project) = @_;
  
  my $description_file = "$project/description";
  
  my $description = $self->_slurp($description_file) || '';
  
  return $description;
}

sub get_project_owner {
  my ($self, $project) = @_;
  
  my $user_id = (stat $project)[4];
  my $user = getpwuid($user_id);
  
  return $user;
}

sub get_project_urls {
  my ($self, $project) = @_;

  open my $fh, '<', "$project/cloneurl"
    or return;
  my @urls = map { chomp; d$_ } <$fh>;
  close $fh;

  return \@urls;
}

sub get_projects {
  my ($self, $home, %opt) = @_;
  my $filter = $opt{filter};
  
  opendir my $dh, e$home
    or croak qq/Can't open directory $home: $!/;
  
  my @projects;
  while (my $project = readdir $dh) {
    next unless $project =~ /\.git$/;
    next unless $self->check_head_link("$home/$project");
    next if defined $filter && $project !~ /\Q$filter\E/;
    push @projects, { path => $project };
  }

  return @projects;
}

sub get_tags {
  my ($self, $project, $limit) = @_;
  my @tags;

  open my $fh, '-|', $self->cmd($project), 'for-each-ref',
    ($limit ? '--count='.($limit+1) : ()), '--sort=-creatordate',
    '--format=%(objectname) %(objecttype) %(refname) '.
    '%(*objectname) %(*objecttype) %(subject)%00%(creator)',
    'refs/tags'
    or return;
  while (my $line = <$fh>) {
    $line = d$line;
    
    my %tag;

    chomp $line;
    my ($refinfo, $creatorinfo) = split(/\0/, $line);
    my ($id, $type, $name, $refid, $reftype, $title) = split(' ', $refinfo, 6);
    my ($creator, $epoch, $tz) =
      ($creatorinfo =~ /^(.*) ([0-9]+) (.*)$/);
    $tag{'fullname'} = $name;
    $name =~ s!^refs/tags/!!;

    $tag{'type'} = $type;
    $tag{'id'} = $id;
    $tag{'name'} = $name;
    if ($type eq "tag") {
      $tag{'subject'} = $title;
      $tag{'reftype'} = $reftype;
      $tag{'refid'}   = $refid;
    } else {
      $tag{'reftype'} = $type;
      $tag{'refid'}   = $id;
    }

    if ($type eq "tag" || $type eq "commit") {
      $tag{'epoch'} = $epoch;
      if ($epoch) {
        $tag{'age'} = $self->_age_string(time - $tag{'epoch'});
      } else {
        $tag{'age'} = "unknown";
      }
    }
    
    $tag{comment_short} = $self->_chop_str($tag{subject}, 30, 5)
      if $tag{subject};

    push @tags, \%tag;
  }
  close $fh;

  return \@tags;
}

sub cmd {
  my ($self, $project) = @_;
  
  return ($self->bin, "--git-dir=$project");
}

sub parse_difftree_raw_line {
  my ($self, $line) = @_;
  my %res;

  if ($line =~ m/^:([0-7]{6}) ([0-7]{6}) ([0-9a-fA-F]{40}) ([0-9a-fA-F]{40}) (.)([0-9]{0,3})\t(.*)$/) {
    $res{'from_mode'} = $1;
    $res{'to_mode'} = $2;
    $res{'from_id'} = $3;
    $res{'to_id'} = $4;
    $res{'status'} = $5;
    $res{'similarity'} = $6;
    if ($res{'status'} eq 'R' || $res{'status'} eq 'C') { # renamed or copied
      ($res{'from_file'}, $res{'to_file'}) = map { $self->_unquote($_) } split("\t", $7);
    } else {
      $res{'from_file'} = $res{'to_file'} = $res{'file'} = $self->_unquote($7);
    }
  }
  elsif ($line =~ s/^(::+)((?:[0-7]{6} )+)((?:[0-9a-fA-F]{40} )+)([a-zA-Z]+)\t(.*)$//) {
    $res{'nparents'}  = length($1);
    $res{'from_mode'} = [ split(' ', $2) ];
    $res{'to_mode'} = pop @{$res{'from_mode'}};
    $res{'from_id'} = [ split(' ', $3) ];
    $res{'to_id'} = pop @{$res{'from_id'}};
    $res{'status'} = [ split('', $4) ];
    $res{'to_file'} = $self->_unquote($5);
  }
  # 'c512b523472485aef4fff9e57b229d9d243c967f'
  elsif ($line =~ m/^([0-9a-fA-F]{40})$/) {
    $res{'commit'} = $1;
  }

  return wantarray ? %res : \%res;
}

sub parsed_difftree_line {
  my ($self, $line_or_ref) = @_;

  if (ref($line_or_ref) eq "HASH") {
    # pre-parsed (or generated by hand)
    return $line_or_ref;
  } else {
    return $self->parse_difftree_raw_line($line_or_ref);
  }
}

sub parse_ls_tree_line {
  my ($self, $line) = @_;
  my %opts = @_;
  my %res;

  if ($opts{'-l'}) {
    #'100644 blob 0fa3f3a66fb6a137f6ec2c19351ed4d807070ffa   16717  panic.c'
    $line =~ m/^([0-9]+) (.+) ([0-9a-fA-F]{40}) +(-|[0-9]+)\t(.+)$/s;

    $res{'mode'} = $1;
    $res{'type'} = $2;
    $res{'hash'} = $3;
    $res{'size'} = $4;
    if ($opts{'-z'}) {
      $res{'name'} = $5;
    } else {
      $res{'name'} = $self->_unquote($5);
    }
  } else {
    #'100644 blob 0fa3f3a66fb6a137f6ec2c19351ed4d807070ffa  panic.c'
    $line =~ m/^([0-9]+) (.+) ([0-9a-fA-F]{40})\t(.+)$/s;

    $res{'mode'} = $1;
    $res{'type'} = $2;
    $res{'hash'} = $3;
    if ($opts{'-z'}) {
      $res{'name'} = $4;
    } else {
      $res{'name'} = $self->_unquote($4);
    }
  }

  return wantarray ? %res : \%res;
}

sub parse_commit {
  my ($self, $project, $id) = @_;
  
  # Git rev-list
  my @git_rev_list = (
    $self->cmd($project),
    "rev-list",
    "--parents",
    "--header",
    "--max-count=1",
    $id,
    "--"
  );
  open my $fh, "-|", @git_rev_list
    or die "Open git-rev-list failed";
  
  # Parse rev-list result
  local $/ = "\0";
  my $content = <$fh>;
  $content = d$content;
  my %commit = $self->parse_commit_text($content, 1);
  close $fh;

  return wantarray ? %commit : \%commit;
}

sub parse_commit_text {
  my ($self, $commit_text, $withparents) = @_;
  my @commit_lines = split '\n', $commit_text;
  my %commit;

  pop @commit_lines; # Remove '\0'

  if (! @commit_lines) {
    return;
  }

  my $header = shift @commit_lines;
  if ($header !~ m/^[0-9a-fA-F]{40}/) {
    return;
  }
  ($commit{'id'}, my @parents) = split ' ', $header;
  while (my $line = shift @commit_lines) {
    last if $line eq "\n";
    if ($line =~ m/^tree ([0-9a-fA-F]{40})$/) {
      $commit{'tree'} = $1;
    } elsif ((!defined $withparents) && ($line =~ m/^parent ([0-9a-fA-F]{40})$/)) {
      push @parents, $1;
    } elsif ($line =~ m/^author (.*) ([0-9]+) (.*)$/) {
      $commit{'author'} = $1;
      $commit{'author_epoch'} = $2;
      $commit{'author_tz'} = $3;
      if ($commit{'author'} =~ m/^([^<]+) <([^>]*)>/) {
        $commit{'author_name'}  = $1;
        $commit{'author_email'} = $2;
      } else {
        $commit{'author_name'} = $commit{'author'};
      }
    } elsif ($line =~ m/^committer (.*) ([0-9]+) (.*)$/) {
      $commit{'committer'} = $1;
      $commit{'committer_epoch'} = $2;
      $commit{'committer_tz'} = $3;
      if ($commit{'committer'} =~ m/^([^<]+) <([^>]*)>/) {
        $commit{'committer_name'}  = $1;
        $commit{'committer_email'} = $2;
      } else {
        $commit{'committer_name'} = $commit{'committer'};
      }
    }
  }
  if (!defined $commit{'tree'}) {
    return;
  };
  $commit{'parents'} = \@parents;
  $commit{'parent'} = $parents[0];

  for my $title (@commit_lines) {
    $title =~ s/^    //;
    if ($title ne "") {
      $commit{'title'} = $self->_chop_str($title, 80, 5);
      # remove leading stuff of merges to make the interesting part visible
      if (length($title) > 50) {
        $title =~ s/^Automatic //;
        $title =~ s/^merge (of|with) /Merge ... /i;
        if (length($title) > 50) {
          $title =~ s/(http|rsync):\/\///;
        }
        if (length($title) > 50) {
          $title =~ s/(master|www|rsync)\.//;
        }
        if (length($title) > 50) {
          $title =~ s/kernel.org:?//;
        }
        if (length($title) > 50) {
          $title =~ s/\/pub\/scm//;
        }
      }
      $commit{'title_short'} = $self->_chop_str($title, 50, 5);
      last;
    }
  }
  if (! defined $commit{'title'} || $commit{'title'} eq "") {
    $commit{'title'} = $commit{'title_short'} = '(no commit message)';
  }
  # remove added spaces
  for my $line (@commit_lines) {
    $line =~ s/^    //;
  }
  $commit{'comment'} = \@commit_lines;

  my $age = time - $commit{'committer_epoch'};
  $commit{'age'} = $age;
  $commit{'age_string'} = $self->_age_string($age);
  my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime($commit{'committer_epoch'});
  if ($age > 60*60*24*7*2) {
    $commit{'age_string_date'} = sprintf "%4i-%02u-%02i", 1900 + $year, $mon+1, $mday;
    $commit{'age_string_age'} = $commit{'age_string'};
  } else {
    $commit{'age_string_date'} = $commit{'age_string'};
    $commit{'age_string_age'} = sprintf "%4i-%02u-%02i", 1900 + $year, $mon+1, $mday;
  }
  return %commit;
}

sub parse_commits {
  my ($self, $project, $cid, $maxcount, $skip, $file, @args) = @_;

  # git rev-list
  $maxcount ||= 1;
  $skip ||= 0;
  open my $fh, "-|", $self->cmd($project), "rev-list",
    "--header",
    @args,
    ("--max-count=" . $maxcount),
    ("--skip=" . $skip),
    $cid,
    "--",
    ($file ? ($file) : ())
    or die_error(500, "Open git-rev-list failed");

  # Parse rev-list results
  local $/ = "\0";
  my @commits;
  while (my $line = <$fh>) {
    $line = d$line;
    my %commit = $self->parse_commit_text($line);
    push @commits, \%commit;
  }
  close $fh;

  return \@commits;
}

sub parse_date {
  my $self = shift;
  my $epoch = shift;
  my $tz = shift || "-0000";

  my %date;
  my @months = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
  my @days = ("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat");
  my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime($epoch);
  $date{'hour'} = $hour;
  $date{'minute'} = $min;
  $date{'mday'} = $mday;
  $date{'day'} = $days[$wday];
  $date{'month'} = $months[$mon];
  $date{'rfc2822'}   = sprintf "%s, %d %s %4d %02d:%02d:%02d +0000",
                       $days[$wday], $mday, $months[$mon], 1900+$year, $hour ,$min, $sec;
  $date{'mday-time'} = sprintf "%d %s %02d:%02d",
                       $mday, $months[$mon], $hour ,$min;
  $date{'iso-8601'}  = sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ",
                       1900+$year, 1+$mon, $mday, $hour ,$min, $sec;

  my ($tz_sign, $tz_hour, $tz_min) =
    ($tz =~ m/^([-+])(\d\d)(\d\d)$/);
  $tz_sign = ($tz_sign eq '-' ? -1 : +1);
  my $local = $epoch + $tz_sign*((($tz_hour*60) + $tz_min)*60);
  ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime($local);
  $date{'hour_local'} = $hour;
  $date{'minute_local'} = $min;
  $date{'tz_local'} = $tz;
  $date{'iso-tz'} = sprintf("%04d-%02d-%02d %02d:%02d:%02d %s",
                            1900+$year, $mon+1, $mday,
                            $hour, $min, $sec, $tz);
  return %date;
}

sub parse_tag {
  my ($self, $project, $tag_id) = @_;
  my %tag;
  my @comment;
  
  my @git_cat_file = ($self->cmd($project), "cat-file", "tag", $tag_id);
  
  open my $fh, "-|", @git_cat_file or return;
  $tag{'id'} = $tag_id;
  while (my $line = <$fh>) {
    $line = d$line;
    
    chomp $line;
    if ($line =~ m/^object ([0-9a-fA-F]{40})$/) {
      $tag{'object'} = $1;
    } elsif ($line =~ m/^type (.+)$/) {
      $tag{'type'} = $1;
    } elsif ($line =~ m/^tag (.+)$/) {
      $tag{'name'} = $1;
    } elsif ($line =~ m/^tagger (.*) ([0-9]+) (.*)$/) {
      $tag{'author'} = $1;
      $tag{'author_epoch'} = $2;
      $tag{'author_tz'} = $3;
      if ($tag{'author'} =~ m/^([^<]+) <([^>]*)>/) {
        $tag{'author_name'}  = $1;
        $tag{'author_email'} = $2;
      } else {
        $tag{'author_name'} = $tag{'author'};
      }
    } elsif ($line =~ m/--BEGIN/) {
      push @comment, $line;
      last;
    } elsif ($line eq "") {
      last;
    }
  }
  my $comment = <$fh>;
  push @comment, d$comment;
  $tag{'comment'} = \@comment;
  close $fh or return;
  if (!defined $tag{'name'}) {
    return
  };
  return \%tag;
}

sub snapshot_name {
  my ($self, $project, $cid) = @_;

  my $name = $project;
  $name =~ s,([^/])/*\.git$,$1,;
  $name = basename($name);
  # sanitize name
  $name =~ s/[[:cntrl:]]/?/g;

  my $ver = $cid;
  if ($cid =~ /^[0-9a-fA-F]+$/) {
    my $full_hash = $self->get_id($project, $cid);
    if ($full_hash =~ /^$cid/ && length($cid) > 7) {
      $ver = $self->get_short_id($project, $cid);
    }
  } elsif ($cid =~ m!^refs/tags/(.*)$!) {
    $ver = $1;
  } else {
    if ($cid =~ m!^refs/(?:heads|remotes)/(.*)$!) {
      $ver = $1;
    }
    $ver .= '-' . $self->get_short_id($project, $cid);
  }
  $ver =~ s!/!.!g;

  $name = "$name-$ver";

  return wantarray ? ($name, $name) : $name;
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

sub _chop_str {
  my $self = shift;
  my $str = shift;
  my $len = shift;
  my $add_len = shift || 10;
  my $where = shift || 'right'; # 'left' | 'center' | 'right'

  if ($where eq 'center') {
    return $str if ($len + 5 >= length($str)); # filler is length 5
    $len = int($len/2);
  } else {
    return $str if ($len + 4 >= length($str)); # filler is length 4
  }

  # regexps: ending and beginning with word part up to $add_len
  my $endre = qr/.{$len}\w{0,$add_len}/;
  my $begre = qr/\w{0,$add_len}.{$len}/;

  if ($where eq 'left') {
    $str =~ m/^(.*?)($begre)$/;
    my ($lead, $body) = ($1, $2);
    if (length($lead) > 4) {
      $lead = " ...";
    }
    return "$lead$body";

  } elsif ($where eq 'center') {
    $str =~ m/^($endre)(.*)$/;
    my ($left, $str)  = ($1, $2);
    $str =~ m/^(.*?)($begre)$/;
    my ($mid, $right) = ($1, $2);
    if (length($mid) > 5) {
      $mid = " ... ";
    }
    return "$left$mid$right";

  } else {
    $str =~ m/^($endre)(.*)$/;
    my $body = $1;
    my $tail = $2;
    if (length($tail) > 4) {
      $tail = "... ";
    }
    return "$body$tail";
  }
}

sub _mode_str {
  my $self = shift;
  my $mode = oct shift;

  if ($self->_S_ISGITLINK($mode)) {
    return 'm---------';
  } elsif (S_ISDIR($mode & S_IFMT)) {
    return 'drwxr-xr-x';
  } elsif (S_ISLNK($mode)) {
    return 'lrwxrwxrwx';
  } elsif (S_ISREG($mode)) {
    # git cares only about the executable bit
    if ($mode & S_IXUSR) {
      return '-rwxr-xr-x';
    } else {
      return '-rw-r--r--';
    };
  } else {
    return '----------';
  }
}

sub file_type {
  my ($self, $mode) = @_;

  if ($mode !~ m/^[0-7]+$/) {
    return $mode;
  } else {
    $mode = oct $mode;
  }

  if ($self->_S_ISGITLINK($mode)) {
    return "submodule";
  } elsif (S_ISDIR($mode & S_IFMT)) {
    return "directory";
  } elsif (S_ISLNK($mode)) {
    return "symlink";
  } elsif (S_ISREG($mode)) {
    return "file";
  } else {
    return "unknown";
  }
}

sub file_type_long {
  my ($self, $mode) = @_;

  if ($mode !~ m/^[0-7]+$/) {
    return $mode;
  } else {
    $mode = oct $mode;
  }

  if (S_ISGITLINK($mode)) {
    return "submodule";
  } elsif (S_ISDIR($mode & S_IFMT)) {
    return "directory";
  } elsif (S_ISLNK($mode)) {
    return "symlink";
  } elsif (S_ISREG($mode)) {
    if ($mode & S_IXUSR) {
      return "executable";
    } else {
      return "file";
    };
  } else {
    return "unknown";
  }
}

sub search_projects {
  my ($self, %opt) = @_;
  my $dirs = $opt{dirs};
  my $max_depth = $opt{max_depth};
  
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
          if ($self->check_head_link($path)) {
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

sub _slurp {
  my ($self, $file) = @_;
  
  open my $fh, '<', $file
    or die qq/Can't open file "$file": $!/;
  my $content = do { local $/; <$fh> };
  $content = d$content;
  close $fh;
  
  return $content;
}

sub _unquote {
  my ($self, $str) = @_;

  sub unq {
    my $seq = shift;
    my %es = ( # character escape codes, aka escape sequences
      't' => "\t",   # tab            (HT, TAB)
      'n' => "\n",   # newline        (NL)
      'r' => "\r",   # return         (CR)
      'f' => "\f",   # form feed      (FF)
      'b' => "\b",   # backspace      (BS)
      'a' => "\a",   # alarm (bell)   (BEL)
      'e' => "\e",   # escape         (ESC)
      'v' => "\013", # vertical tab   (VT)
    );

    if ($seq =~ m/^[0-7]{1,3}$/) {
      # octal char sequence
      return chr(oct($seq));
    } elsif (exists $es{$seq}) {
      # C escape sequence, aka character escape code
      return $es{$seq};
    }
    # quoted ordinary character
    return $seq;
  }

  if ($str =~ m/^"(.*)"$/) {
    # needs unquoting
    $str = $1;
    $str =~ s/\\([^0-7]|[0-7]{1,3})/unq($1)/eg;
  }
  return $str;
}

sub _S_ISGITLINK {
  my ($self, $mode) = @_;

  return (($mode & S_IFMT) == S_IFGITLINK)
}

sub _timestamp {
  my ($self, $date) = @_;
  my $strtime = $date->{'rfc2822'};

  my $localtime_format = '(%02d:%02d %s)';
  if ($date->{'hour_local'} < 6) {
    $localtime_format = '(%02d:%02d %s)';
  }
  $strtime .= ' ' .
              sprintf($localtime_format,
                      $date->{'hour_local'}, $date->{'minute_local'}, $date->{'tz_local'});

  return $strtime;
}

sub _untabify {
  my ($self, $line) = @_;

  while ((my $pos = index($line, "\t")) != -1) {
    if (my $count = (8 - ($pos % 8))) {
      my $spaces = ' ' x $count;
      $line =~ s/\t/$spaces/;
    }
  }

  return $line;
}

1;
