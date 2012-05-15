package Gitweblite::Main;
use Mojo::Base 'Mojolicious::Controller';
use File::Basename 'dirname';
use Carp 'croak';

# Encode
use Encode qw/encode decode/;
sub e($) { encode('UTF-8', shift) }
sub d($) { decode('UTF-8', shift) }

has diff_opts => sub { ['-M'] };
has prevent_xss => 0;

sub blob {
  my $self = shift;

  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $id_file = $self->param('id_file');
  
  # Git
  my $git = $self->app->git;

  # ID and file
  my $refs = $git->get_references($project);
  my $id;
  my $file;
  for my $rs (values %$refs) {
    for my $ref (@$rs) {
      $ref =~ s#^heads/##;
      $ref =~ s#^tags/##;
      if ($id_file =~ s#^\Q$ref(/|$)##) {
        $id = $ref;
        $file = $id_file;
        last;
      }      
    }
  }
  unless (defined $id) {
    if ($id_file =~ s#(^[^/]+)(/|$)##) {
      $id = $1;
      $file = $id_file;
    }
  }

  # Blob plain
  if ($self->stash('plain')) {
    # Blob id
    my $bid = $git->get_id_by_path($project, $id, $file, "blob")
      or croak "Cannot find file";
    open my $fh, "-|", $git->cmd($project), "cat-file", "blob", $bid
      or croak "Open git-cat-file blob '$bid' failed";

    # content-type (can include charset)
    my $type = $git->blob_contenttype($fh, $file);

    # "save as" filename, even when no $file is given
    my $save_as = "$id";
    if (defined $file) { $save_as = $file }
    elsif ($type =~ m/^text\//) { $save_as .= '.txt' }

    my $sandbox = $self->prevent_xss &&
      $type !~ m!^(?:text/[a-z]+|image/(?:gif|png|jpeg))(?:[ ;]|$)!;

    # serve text/* as text/plain
    if ($self->prevent_xss &&
        ($type =~ m!^text/[a-z]+\b(.*)$! ||
         ($type =~ m!^[a-z]+/[a-z]\+xml\b(.*)$! && -T $fh))) {
      my $rest = $1;
      $rest = defined $rest ? $rest : '';
      $type = "text/plain$rest";
    }
    
    my $content = do { local $/; <$fh> };
    my $content_disposition = $sandbox ? 'attachment' : 'inline';
    $content_disposition .= "; filename=$save_as";
    $self->res->headers->content_disposition($content_disposition);
    $self->res->headers->content_type($type);
    $self->render_data($content);
  }
  
  # Blob
  else {
    # Blob id
    my $bid = $git->get_id_by_path($project, $id, $file, "blob")
      or croak "Cannot find file";
    
    # Blob
    my @git_cat_file = (
      $git->cmd($project),
      "cat-file",
      "blob",
      $bid
    );
    open my $fh, "-|", @git_cat_file
      or croak "Couldn't cat $file, $bid";
    
    my $mimetype = $git->blob_mimetype($fh, $file);
    # Redirect to blob plane
    if ($mimetype !~ m!^(?:text/|image/(?:gif|png|jpeg)$)! && -B $fh) {
      close $fh;
      my $url = $self->url_for('/blob_plain', home => $home,
        project => $project, id => $id, file => $file);
      return $self->redirect_to($url);
    }
    
    # Commit
    my $commit = $git->parse_commit($project, $id);

    # Parse line
    my @lines;
    while (my $line = <$fh>) {
      $line = d$line;
      chomp $line;
      $line = $git->_untabify($line);
      push @lines, $line;
    }
    
    # Render
    $self->render(
      home => $home,
      home_ns => $home_ns,
      project => $project,
      project_ns => $project_ns,
      id => $id,
      bid => $bid,
      file => $file,
      commit => $commit,
      lines => \@lines,
      mimetype => $mimetype
    );
  }
}

sub blobdiff {
  my $self = shift;

  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $diff = $self->param('diff');
  my $file = $self->param('file');
  my $from_file = $file;
  my $plain = $self->param('plain');
  my $from_id;
  my $id;
  if ($diff =~ /\.\./) { ($from_id, $id) = $diff =~ /(.+)\.\.(.+)/ }
  else { $id = $diff }
  
  # Git
  my $git = $self->app->git;

  my $fh;
  my @difftree;
  my %diffinfo;
  
  my $bid;
  my $from_bid;

  if (defined $id && defined $from_id) {
    if (defined $file) {
      # git diff tree
      my @git_diff_tree = ($git->cmd($project), "diff-tree", '-r',
        @{$self->diff_opts}, $from_id, $id, "--",
        (defined $from_file ? $from_file : ()), $file
      );
      
      open $fh, "-|", @git_diff_tree
        or croak 500, "Open git-diff-tree failed";
      @difftree = map { chomp; d$_ } <$fh>;
      close $fh
        or croak 404, "Reading git-diff-tree failed";
      @difftree
        or croak 404, "Blob diff not found";

    } elsif (defined $bid && $bid =~ /[0-9a-fA-F]{40}/) {

      # read filtered raw output
      open $fh, "-|", $git->cmd($project), "diff-tree", '-r', @{$self->diff_opts},
          $from_id, $id, "--"
        or croak "Open git-diff-tree failed";
      @difftree =
        grep { /^:[0-7]{6} [0-7]{6} [0-9a-fA-F]{40} $bid/ }
        map { chomp; d$_ } <$fh>;
      close $fh
        or croak("Reading git-diff-tree failed");
      @difftree
        or croak("Blob diff not found");

    } else {
      croak "Missing one of the blob diff parameters";
    }

    if (@difftree > 1) {
      croak "Ambiguous blob diff specification";
    }

    %diffinfo = $git->parse_difftree_raw_line($difftree[0]);
    $from_file ||= $diffinfo{from_file} || $file;
    $file   ||= $diffinfo{to_file};

    $from_bid ||= $diffinfo{from_id};
    $bid        ||= $diffinfo{to_id};

    # open patch output
    open $fh, "-|", $git->cmd($project), "diff-tree", '-r', @{$self->diff_opts},
      '-p', (!$plain ? "--full-index" : ()),
      $from_id, $id,
      "--", (defined $from_file ? $from_file : ()), $file
      or croak_error(500, "Open git-diff-tree failed");
  }
  
  if (!%diffinfo) {
    croak '404 Not Found', "Missing one of the blob diff parameters";
  }
  
  my $commit = $git->parse_commit($project, $id);
  
  if ($plain) {
    my $content = do { local $/; <$fh> };
    close $fh;
    my $content_disposition .= "inline; filename=$file";
    $self->res->headers->content_disposition($content_disposition);
    $self->res->headers->content_type("text/plain; charset=UTF-8");
    $self->render(data => $content);
  }
  else {
    # patch
    my @lines = <$fh>;
    close $fh;
    my $lines = $self->_parse_blobdiff_lines(\@lines);

    $self->render(
      '/blobdiff',
      home => $home,
      home_ns => $home_ns,
      project => $project,
      project_ns => $project_ns,
      id => $id,
      from_id => $from_id,
      file => $file,
      commit => $commit,
      diffinfo => \%diffinfo,
      lines => $lines
    );
  }
}

sub commit {
  my $self = shift;

  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $id = $self->param('id');
  
  # Git
  my $git = $self->app->git;

  # Project information
  my $project_description = $git->get_project_description($project);
  my $project_owner = $git->get_project_owner($project);
  
  # Commit
  my $commit = $git->parse_commit($project, $id);
  my %committer_date = $commit ? $git->parse_date($commit->{committer_epoch}, $commit->{committer_tz}) : ();
  my %author_date = $commit ? $git->parse_date($commit->{author_epoch}, $commit->{author_tz}) : ();
  $commit->{author_date} = $git->_timestamp(\%author_date);
  $commit->{committer_date} = $git->_timestamp(\%committer_date);
  
  # References
  my $refs = $git->get_references($project);
  
  # Diff tree
  my $parent = $commit->{parent};
  my $parents = $commit->{parents};
  my $difftrees = $git->get_difftree($project, $commit->{id}, $parent, $parents);
  
  # Render
  $self->render(
    home => $home,
    home_ns => $home_ns,
    project => $project,
    project_ns => $project_ns,
    project_owner => $project_owner,
    id => $id,
    id => $id,
    commit => $commit,
    refs => $refs,
    difftrees => $difftrees,
  );
}

sub commitdiff {
  my $self = shift;
  
  # Paramters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $diff = $self->param('diff');
  my $from_id;
  my $id;
  if ($diff =~ /\.\./) {
    ($from_id, $id) = $diff =~ /(.+)\.\.(.+)/;
  }
  else { $id = $diff }
  
  # Git
  my $git = $self->app->git;
  
  # Commit
  my $commit = $git->parse_commit($project, $id)
    or croak 404, "Unknown commit object";
  my %author_date = %$commit
    ? $git->parse_date($commit->{author_epoch}, $commit->{author_tz})
    : ();
  my %committer_date = %$commit
    ? $git->parse_date($commit->{committer_epoch}, $commit->{committer_tz})
    : ();
  $commit->{author_date} = $git->_timestamp(\%author_date);
  $commit->{committer_date} = $git->_timestamp(\%committer_date);
  $from_id = $commit->{parent} unless defined $from_id;
  
  # Plain text
  my $plain = $self->param('plain');
  if ($plain) {
    # git diff-tree plain output
    open my $fh, "-|", $git->cmd($project), "diff-tree", '-r', @{$self->diff_opts},
        '-p', $from_id, $id, "--"
      or croak 500, "Open git-diff-tree failed";
    

    my $content = do { local $/; <$fh> };
    my $content_disposition .= "inline; filename=$id";
    $self->res->headers->content_disposition($content_disposition);
    $self->res->headers->content_type("text/plain;charset=UTF-8");
    $self->render_data($content);
  }
  
  # HTML
  else {
    # git diff-tree output
    open my $fh, "-|", $git->cmd($project), "diff-tree", '-r', @{$self->diff_opts},
        "--no-commit-id", "--patch-with-raw", "--full-index",
        $from_id, $id, "--"
      or croak 500, "Open git-diff-tree failed";

    # Parse output
    my @diffinfos;
    while (my $line = <$fh>) {
      $line = d$line;
      chomp $line;
      last unless $line;
      push @diffinfos, scalar $git->parse_difftree_raw_line($line);
    }
    
    my $difftrees = $git->get_difftree($project,
      $id,$commit->{parent}, $commit->{parents});
    
    my @blobdiffs;
    for my $diffinfo (@diffinfos) {
      
      my $from_file = $diffinfo->{from_file};
      my $file = $diffinfo->{to_file};
      my $from_bid = $diffinfo->{from_id};
      my $bid = $diffinfo->{to_id};
      
      my @git_diff_tree = ($git->cmd($project), "diff-tree", '-r',
        @{$self->diff_opts}, '-p', (!$plain ? "--full-index" : ()), $from_id, $id,
        "--", (defined $from_file ? $from_file : ()), $file
      );
      open $fh, "-|", @git_diff_tree
        or croak 500, "Open git-diff-tree failed";
      
      my @lines = <$fh>;
      close $fh;
      push @blobdiffs, {file => $file, lines => $self->_parse_blobdiff_lines(\@lines)};
    }

    # References
    my $refs = $git->get_references($project);
    
    # Render
    $self->render(
      'commitdiff',
      home => $home,
      home_ns => $home_ns,
      project => $project,
      project_ns => $project_ns,
      from_id => $from_id,
      id => $id,
      commit => $commit,
      difftrees => $difftrees,
      blobdiffs => \@blobdiffs,
      refs => $refs
    );
  }
}

sub home {
  my $self = shift;

  # Search git repositories
  my $dirs = $self->app->config('search_dirs');
  my $max_depth = $self->app->config('search_max_depth');
  my $projects = $self->app->git->search_projects(
    dirs => $dirs,
    max_depth => $max_depth
  );
  
  my $homes = {};
  $homes->{$_->{home}} = 1 for @$projects;

  $self->render(homes => [keys %$homes]);
}


sub heads {
  my $self = shift;
  
  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  
  # Git
  my $git = $self->app->git;
  
  # Ref names
  my $heads  = $git->get_heads($project);
  
  # Render
  $self->render(
    home => $home,
    home_ns => $home_ns,
    project => $project,
    project_ns => $project_ns,
    heads => $heads,
  );
}

sub log {
  my ($self, %opt) = @_;

  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $id = $self->param('id');
  my $page = $self->param('page');
  $page = 0 if !defined $page;
  my $short = $self->param('short');
  
  # Git
  my $git = $self->app->git;
  
  # Commit
  my $commit = $git->parse_commit($project, $id);
  
  # Commits
  my $page_count = $short ? 50 : 20;
  my $commits = $git->parse_commits(
    $project, $commit->{id},$page_count, $page_count * $page);

  for my $commit (@$commits) {
    my %author_date = %$commit
      ? $git->parse_date($commit->{author_epoch}, $commit->{author_tz})
      : ();
    $commit->{author_date} = $git->_timestamp(\%author_date);
  }
  
  # References
  my $refs = $git->get_references($project);

  # Render
  my $template = $short ? 'main/shortlog' : 'main/log';
  $self->render(
    $template,
    home => $home,
    home_ns => $home_ns,
    project => $project,
    project_ns => $project_ns,
    id => $id,
    commits => $commits,
    refs => $refs,
    page => $page,
    page_count => $page_count
  );
};

sub projects {
  my $self = shift;
  
  # Parameters
  my $home_ns = $self->param('home');
  my $home = "/$home_ns";

  # Git
  my $git = $self->app->git;
  
  # Fill project information
  my @projects = $git->get_projects($home);
  @projects = $git->fill_projects($home, \@projects);
  
  # Fill owner and HEAD commit id
  for my $project (@projects) {
    my $pname = "$home/$project->{path}";
    $project->{path_abs_ns} = "$home_ns/$project->{path}";
    $project->{owner} = $git->get_project_owner($pname);
    my $head_commit = $git->parse_commit($pname, "HEAD");
    $project->{head_id} = $head_commit->{id}
  }
  
  # Render
  $self->render(
    home => $home,
    home_ns => $home_ns,
    projects => \@projects
  );
}

sub snapshot {
  my $self = shift;

  # Parameter
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $id = $self->param('id');
  
  # Git
  my $git = $self->app->git;

  # Object type
  my $type = $git->get_object_type($project, "$id^{}");
  if (!$type) { croak 404, 'Object does not exist' }
  elsif ($type eq 'blob') { croak 400, 'Object is not a tree-ish' }
  
  
  my ($name, $prefix) = $git->snapshot_name($project, $id);
  my $file = "$name.tar.gz";
  my $cmd = $self->_quote_command(
    $git->cmd($project), 'archive', "--format=tar", "--prefix=$prefix/", $id
  );
  $cmd .= ' | ' . $self->_quote_command('gzip', '-n');

  $file =~ s/(["\\])/\\$1/g;

  open my $fh, "-|", $cmd
    or croak 500, "Execute git-archive failed";
  
  # Write chunk
  $self->res->headers->content_type('application/x-tar');
  $self->res->headers->content_disposition(qq/attachment; filename="$file"/);
  my $cb;
  $cb = sub {
    my $c = shift;
    my $size = 500 * 1024;
    my $length = sysread($fh, my $buffer, $size);
    unless (defined $length) {
      close $fh;
      undef $cb;
      return;
    }
    $c->write_chunk($buffer, $cb);
  };
  $self->$cb;
}

sub summary {
  my $self = shift;
  
  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  
  # Git
  my $git = $self->app->git;
  
  # HEAd commit
  my $project_description = $git->get_project_description($project);
  my $project_owner = $git->get_project_owner($project);
  my $head_commit = $git->parse_commit($project, "HEAD");
  my %committer_date = $head_commit
    ? $git->parse_date($head_commit->{committer_epoch}, $head_commit->{committer_tz})
    : ();
  my $last_change = $git->_timestamp(\%committer_date);
  my $head_id = $head_commit->{id};
  my $urls = $git->get_project_urls($project);
  
  # Commits
  my $commit_count = 20;
  my $commits = $head_id ? $git->parse_commits($project, $head_id, $commit_count) : ();

  # References
  my $refs = $git->get_references($project);
  
  # Tags
  my $tag_count = 20;
  my $tags  = $git->get_tags($project, $tag_count - 1);

  # Heads
  my $head_count = 20;
  my $heads = $git->get_heads($project, $head_count - 1);
  
  # Render
  $self->render(
    home => $home,
    home_ns => $home_ns,
    project => $project,
    project_ns => $project_ns,
    project_description => $project_description,
    project_owner => $project_owner,
    last_change => $last_change,
    urls => $urls,
    commits => $commits,
    tags => $tags,
    head_id => $head_id,
    heads => $heads,
    refs => $refs,
    commit_count => $commit_count,
    tag_count => $tag_count,
    head_count => $head_count
  );
}

sub tag {
  my $self = shift;
  
  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $id = $self->param('id');
  
  # Git
  my $git = $self->app->git;
  
  # Ref names
  my $tag  = $git->parse_tag($project, $id);
  my %author_date = %$tag
    ? $git->parse_date($tag->{author_epoch}, $tag->{author_tz})
    : ();
  my $author_date = $git->_timestamp(\%author_date);
  $tag->{author_date} = $author_date;
  
  # Render
  $self->render(
    home => $home,
    home_ns => $home_ns,
    project => $project,
    project_ns => $project_ns,
    tag => $tag,
  );
}

sub tags {
  my $self = shift;
  
  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  
  # Git
  my $git = $self->app->git;
  
  # Ref names
  my $tags  = $git->get_tags($project);
  
  # Render
  $self->render(
    home => $home,
    home_ns => $home_ns,
    project => $project,
    project_ns => $project_ns,
    tags => $tags,
  );
}

sub tree {
  my $self = shift;
  
  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $id_dir = $self->param('id_dir');

  # Git
  my $git = $self->app->git;
  
  # References
  my $refs = $git->get_references($project);
  my $id;
  my $dir;
  for my $rs (values %$refs) {
    for my $r (@$rs) {
      my $ref = $r;
      $ref =~ s#^heads/##;
      $ref =~ s#^tags/##;
      if ($id_dir =~ s#^\Q$ref(/|$)##) {
        $id = $ref;
        $dir = $id_dir;
        last;
      }      
    }
  }
  unless (defined $id) {
    if ($id_dir =~ s#(^[^/]+)(/|$)##) {
      $id = $1;
      $dir = $id_dir;
    }
  }
  
  my $tid;
  my $commit = $git->parse_commit($project, $id);
  unless (defined $tid) {
    if (defined $dir && $dir ne '') {
      $tid = $git->get_id_by_path($project, $id, $dir, "tree");
    }
    else { $tid = $commit->{tree} }
  }
  croak 404, "No such tree" unless defined $tid;

  my @entries = ();
  my $show_sizes = 0;
  {
    open my $fh, "-|", $git->cmd($project), "ls-tree", '-z',
      ($show_sizes ? '-l' : ()), $tid
      or croak 500, "Open git-ls-tree failed";
    local $/ = "\0";
    @entries = map { chomp; d$_ } <$fh>;
    close $fh
      or croak 404, "Reading tree failed";
  }
  
  my @trees;
  for my $line (@entries) {
    my %tree = $git->parse_ls_tree_line($line, -z => 1, -l => $show_sizes);
    $tree{mode_str} = $git->_mode_str($tree{mode});
    push @trees, \%tree;
  }
  
  
  $self->render(
    home => $home,
    home_ns => $home_ns,
    project => $project,
    project_ns => $project_ns,
    dir => $dir,
    id => $id,
    tid => $tid,
    commit => $commit,
    trees => \@trees,
    refs => $refs
  );
}

sub _parse_blobdiff_lines {
  my ($self, $lines_raw) = @_;
  
  my @lines;
  for my $line (@$lines_raw) {
    $line = d$line;
    chomp $line;
    my $class;
    
    if ($line =~ /^diff \-\-git /) { $class = 'diff header' }
    elsif ($line =~ /^index /) { $class = 'diff extended_header' }
    elsif ($line =~ /^\+/) { $class = 'diff to_file' }
    elsif ($line =~ /^\-/) { $class = 'diff from_file' }
    elsif ($line =~ /^\@\@/) { $class = 'diff chunk_header' }
    elsif ($line =~ /^Binary files/) { $class = 'diff binary_file' }
    else { $class = 'diff' }
    push @lines, {value => $line, class => $class};
  }
  
  return \@lines;
}

sub _parse_params {
  my $self = shift;
  my $params = {map { $_ => scalar $self->param($_) } $self->param};
  return $params;
}

sub _quote_command {
  my $self = shift;
  return join(' ',
    map { my $a = $_; $a =~ s/(['!])/'\\$1'/g; "'$a'" } @_ );
}

1;
