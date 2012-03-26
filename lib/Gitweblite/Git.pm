package Gitweblite::Git;
use Mojo::Base -base;

use Carp 'croak';
use Encode qw/encode decode/;
use Fcntl ':mode';
use constant {
  S_IFINVALID => 0030000,
  S_IFGITLINK => 0160000,
};

sub e($) { encode('UTF-8', shift) }

has 'bin';

my $conf = {};
my $export_ok = $conf->{export_ok} || '';
my $export_auth_hook = $conf->{export_ok} || undef;
my @diff_opts = ('-M');

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

sub fill_projects {
  my ($self, $root, $ps) = @_;

  my @projects;
  for my $project (@$ps) {
    my (@activity) = $self->get_last_activity($root, $project->{'path'});
    next unless @activity;
    ($project->{'age'}, $project->{'age_string'}) = @activity;
    if (!defined $project->{'descr'}) {
      my $descr = $self->get_project_description($root, $project->{'path'}) || "";
      $project->{'descr_long'} = $descr;
      $project->{'descr'} = $self->_chop_str($descr, 25, 5);
    }

    push @projects, $project;
  }

  return @projects;
}

sub get_difftree {
  my ($self, $root, $project, $cid, $parent, $parents) = @_;
  
  # Execute "git diff-tree"
  my @git_diff_tree = (
    $self->git($root, $project),
    "diff-tree", '-r',
    "--no-commit-id",
    @diff_opts,
    (@$parents <= 1 ? $parent : '-c'),
    $cid,
    "--"
  );
  open my $fd, "-|", @git_diff_tree
    or die "Open git-diff-tree failed";
  my @difftree = map { chomp; $_ } <$fd>;
  close $fd or die "Reading git-diff-tree failed";
  
  # Parse "git diff-tree" output
  my $diffs = [];
  my @parents = @$parents;
  for my $line (@difftree) {
    my $diff = $self->parsed_difftree_line($line);

    my ($to_mode_oct, $to_mode_str, $to_file_type);
    my ($from_mode_oct, $from_mode_str, $from_file_type);
    if ($diff->{'to_mode'} ne ('0' x 6)) {
      $to_mode_oct = oct $diff->{'to_mode'};
      if (S_ISREG($to_mode_oct)) { # only for regular file
        $to_mode_str = sprintf("%04o", $to_mode_oct & 0777); # permission bits
      }
      $to_file_type = file_type($diff->{'to_mode'});
    }
    if ($diff->{'from_mode'} ne ('0' x 6)) {
      $from_mode_oct = oct $diff->{'from_mode'};
      if (S_ISREG($from_mode_oct)) { # only for regular file
        $from_mode_str = sprintf("%04o", $from_mode_oct & 0777); # permission bits
      }
      $from_file_type = file_type($diff->{'from_mode'});
    }
    
    $diff->{to_mode_str} = $to_mode_str;
    $diff->{to_mode_oct} = $to_mode_oct;
    $diff->{to_file_type} = $to_file_type;
    $diff->{from_mode_str} = $from_mode_str;
    $diff->{from_mode_oct} = $from_mode_oct;
    $diff->{from_file_type} = $from_file_type;

    push @$diffs, $diff;
  }
  
  return $diffs;
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

sub get_last_activity {
  my ($self, $root, $project) = @_;

  my $fd;
  my @git_command = (
    $self->git($root, $project),
    'for-each-ref',
    '--format=%(committer)',
    '--sort=-committerdate',
    '--count=1',
    'refs/heads'  
  );
  open($fd, "-|", @git_command) or return;
  my $most_recent = <$fd>;
  close $fd or return;
  if (defined $most_recent &&
      $most_recent =~ / (\d+) [-+][01]\d\d\d$/) {
    my $timestamp = $1;
    my $age = time - $timestamp;
    return ($age, $self->_age_string($age));
  }
  return (undef, undef);
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

sub get_project_urls {
  my ($self, $root, $project) = @_;

  my $git_dir = "$root/$project";
  open my $fd, '<', "$git_dir/cloneurl"
    or return;
  my @urls = map { chomp; $_ } <$fd>;
  close $fd;

  return \@urls;
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

sub parse_tag {
  my ($self, $root, $project, $tag_id) = @_;
  my %tag;
  my @comment;
  
  my @git_cat_file = ($self->git($root, $project), "cat-file", "tag", $tag_id);
  
  open my $fd, "-|", @git_cat_file or return;
  $tag{'id'} = $tag_id;
  while (my $line = <$fd>) {
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
  push @comment, <$fd>;
  $tag{'comment'} = \@comment;
  close $fd or return;
  if (!defined $tag{'name'}) {
    return
  };
  return \%tag
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

sub _slurp {
  my ($self, $file) = @_;
  
  open my $fh, '<', $file
    or die qq/Can't open file "$file": $!/;
  my $content = do { local $/; <$fh> };
  
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

1;
