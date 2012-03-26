package Gitweblite::Default;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Cache;

has diff_opts => sub { ['-M'] };
has prevent_xss => 0;

sub homes {
  my $self = shift;

  # Search git repositories
  my $dirs = $self->app->config('search_dirs');
  my $max_depth = $self->app->config('search_max_depth');
  my $projects = $self->app->_search_projects(
    dirs => $dirs,
    max_depth => $max_depth
  );
  
  my $homes = {};
  $homes->{$_->{home}} = 1 for @$projects;

  $self->render(homes => [keys %$homes]);
}

sub projects {
  my $self = shift;
  
  # Validation
  my $raw_params = _parse_params($self);
  my $rule = [
    home => ['not_blank']
  ];
  my $vresult = $self->app->validator->validate($raw_params, $rule);
  die unless $vresult->is_ok;
  my $params = $vresult->data;
  my $home = $params->{home};

  # Git
  my $git = $self->app->git;
  
  # Fill project information
  my @projects = $git->get_projects($home);
  @projects = $git->fill_projects($home, \@projects);
  
  # Fill owner
  for my $project (@projects) {
    $project->{owner} = $git->get_project_owner($home, $project->{path});
  }
  
  # Render
  $self->render(
    home => $home,
    projects => \@projects
  );
}

sub summary {
  my $self = shift;
  
  # Validation
  my $raw_params = _parse_params($self);
  my $rule = [
    home => ['not_blank'],
    project => ['not_blank']
  ];
  my $vresult = $self->app->validator->validate($raw_params, $rule);
  die unless $vresult->is_ok;
  my $params = $vresult->data;
  my $home = $params->{home};
  my $project = $params->{project};
  
  # Git
  my $git = $self->app->git;
  
  # HEAd commit
  my $project_description = $git->get_project_description($home, $project);
  my $project_owner = $git->get_project_owner($home, $project);
  my $head_commit = $git->parse_commit($home, $project, "HEAD");
  my %committer_date = %$head_commit
    ? $git->parse_date($head_commit->{committer_epoch}, $head_commit->{committer_tz})
    : ();
  my $last_change = $git->_timestamp(\%committer_date);
  my $head_cid = $head_commit->{id};
  my $urls = $git->get_project_urls($home, $project);
  
  # Commits
  my $commit_count = 20;
  my $commits = $head_cid ? $git->parse_commits($home, $project, $head_cid, $commit_count) : ();
  
  # Ref names
  my $ref_names = {};
  my $tag_count = 20;
  my $tags  = $git->get_tags($home, $project, $tag_count - 1);
  $ref_names->{tag}{$_->{id}} = $_->{name} for @$tags;
  my $head_count = 20;
  my $heads = $git->get_heads($home, $project, $head_count - 1);
  $ref_names->{head}{$_->{id}} = $_->{name} for @$heads;
  
  # Render
  $self->render(
    home => $home,
    project => $project,
    project_description => $project_description,
    project_owner => $project_owner,
    last_change => $last_change,
    urls => $urls,
    commits => $commits,
    tags => $tags,
    head_cid => $head_cid,
    heads => $heads,
    ref_names => $ref_names,
    commit_count => $commit_count,
    tag_count => $tag_count,
    head_count => $head_count
  );
}

sub shortlog { _log(shift, short => 1) }

sub log { _log(shift) }

sub commit {
  my $self = shift;

  # Validation
  my $raw_params = _parse_params($self);
  my $rule = [
    home => ['not_blank'],
    project => ['not_blank'],
    cid => {require => 0} => ['not_blank']
  ];
  my $vresult = $self->app->validator->validate($raw_params, $rule);
  die unless $vresult->is_ok;
  my $params = $vresult->data;
  my $home = $params->{home};
  my $project = $params->{project};
  my $cid = $params->{cid};
  $cid = 'HEAD' unless defined $cid;
  
  # Git
  my $git = $self->app->git;

  # Project information
  my $project_description = $git->get_project_description($home, $project);
  my $project_owner = $git->get_project_owner($home, $project);
  my %commit = $git->parse_commit($home, $project, $cid);
  my %committer_date = %commit ? $git->parse_date($commit{'committer_epoch'}, $commit{'committer_tz'}) : ();
  my %author_date = %commit ? $git->parse_date($commit{'author_epoch'}, $commit{'author_tz'}) : ();
  $commit{author_date} = $git->_timestamp(\%author_date);
  $commit{committer_date} = $git->_timestamp(\%committer_date);
  
  # Ref names
  my $ref_names = {};
  my $tags  = $git->get_tags($home, $project);
  $ref_names->{tag}{$_->{id}} = $_->{name} for @$tags;
  my $heads = $git->get_heads($home, $project);
  $ref_names->{head}{$_->{id}} = $_->{name} for @$heads;
  
  my $parent = $commit{parent};
  my $parents = $commit{parents};
  if (!defined $parent) {
    $parent = "--home";
  }
  
  my $difftrees = $git->get_difftree($home, $project, $cid, $parent, $parents);
  
  $self->render(
    home => $home,
    project => $project,
    project_owner => $project_owner,
    cid => $cid,
    commit => \%commit,
    ref_names => $ref_names,
    difftrees => $difftrees,
    ref_names => $ref_names
  );
}

sub commitdiff {
  my $self = shift;
  
  # Validation
  my $raw_params = _parse_params($self);
  my $rule = [
    home => ['not_blank'],
    project => ['not_blank'],
    cid => {require => 0 } => ['not_blank'],
    from_cid => {require => 0} => ['not_blank']
  ];
  my $vresult = $self->app->validator->validate($raw_params, $rule);
  die unless $vresult->is_ok;
  my $params = $vresult->data;
  my $home = $params->{home};
  my $project = $params->{project};
  my $cid = defined $params->{cid} ? $params->{cid} : 'HEAD';
  my $from_cid = $params->{from_cid};
  
  # Git
  my $git = $self->app->git;
  
  # Commit
  my $commit = $git->parse_commit($home, $project, $cid)
    or die 404, "Unknown commit object";
  my %author_date = %$commit
    ? $git->parse_date($commit->{'author_epoch'}, $commit->{'author_tz'})
    : ();
  my %committer_date = %$commit
    ? $git->parse_date($commit->{'committer_epoch'}, $commit->{'committer_tz'})
    : ();
  $commit->{author_date} = $git->_timestamp(\%author_date);
  $commit->{committer_date} = $git->_timestamp(\%committer_date);
  $from_cid = $commit->{parent} unless defined $from_cid;
  
  # Check plain
  my $plain;
  my $suffix = $self->param('suffix');
  if ($suffix) {
    if ($suffix eq '_plain') { $plain = 1 }
    else { return $self->render('not_found') }
  }
  else { $plain = 0 }
  
  # Plain text
  if ($plain) {
    # git diff-tree plain output
    open my $fd, "-|", $git->git($home, $project), "diff-tree", '-r', @{$self->diff_opts},
        '-p', $from_cid, $cid, "--"
      or die 500, "Open git-diff-tree failed";

    my $content = do { local $/; <$fd> };
    my $content_disposition .= "inline; filename=$cid";
    $self->res->headers->content_disposition($content_disposition);
    $self->res->headers->content_type("text/plain");
    $self->render_data($content);
  }
  
  # HTML
  else {
    # git diff-tree output
    open my $fd, "-|", $git->git($home, $project), "diff-tree", '-r', @{$self->diff_opts},
        "--no-commit-id", "--patch-with-raw", "--full-index",
        $from_cid, $cid, "--"
      or die 500, "Open git-diff-tree failed";

    # Parse output
    my @diffinfos;
    while (my $line = <$fd>) {
      chomp $line;
      last unless $line;
      push @diffinfos, scalar $git->parse_difftree_raw_line($line);
    }
    
    my $difftrees = $git->get_difftree($home, $project,
      $cid,$commit->{parent}, $commit->{parents});
    
    my @blobdiffs;
    for my $diffinfo (@diffinfos) {
      
      my $from_file = $diffinfo->{'from_file'};
      my $file = $diffinfo->{'to_file'};
      my $from_bid = $diffinfo->{'from_id'};
      my $bid = $diffinfo->{'to_id'};
      
      my @git_diff_tree = ($git->git($home, $project), "diff-tree", '-r',
        @{$self->diff_opts}, '-p', (!$plain ? "--full-index" : ()), $from_cid, $cid,
        "--", (defined $from_file ? $from_file : ()), $file
      );
      open $fd, "-|", @git_diff_tree
        or die 500, "Open git-diff-tree failed";
      
      my @lines = map { chomp $_; $_ } <$fd>;
      close $fd;
      push @blobdiffs, {lines => \@lines};
    }

    # Ref names
    my $ref_names = {};
    my $tags  = $git->get_tags($home, $project);
    $ref_names->{tag}{$_->{id}} = $_->{name} for @$tags;
    my $heads = $git->get_heads($home, $project);
    $ref_names->{head}{$_->{id}} = $_->{name} for @$heads;
    
    # Render
    $self->render(
      'commitdiff',
      home => $home,
      project => $project,
      cid => $cid,
      commit => $commit,
      difftrees => $difftrees,
      blobdiffs => \@blobdiffs,
      ref_names => $ref_names
    );
  }
}

sub tree {
  my $self = shift;

  # Validation
  my $raw_params = _parse_params($self);
  my $rule = [
    home => ['not_blank'],
    project => ['not_blank'],
    cid => {require => 0 } => ['not_blank'],
    dir => {require => 0 } => ['not_blank'],
    tid => {require => 0 } => ['not_blank']
  ];
  my $vresult = $self->app->validator->validate($raw_params, $rule);
  die unless $vresult->is_ok;
  my $params = $vresult->data;
  my $home = $params->{home};
  my $project = $params->{project};
  my $cid = $params->{cid};
  $cid = "HEAD" unless defined $cid;
  my $dir = $params->{dir};
  my $tid = $params->{tid};
  
  # Git
  my $git = $self->app->git;

  my $commit = $git->parse_commit($home, $project, $cid);
  
  unless (defined $tid) {
    if (defined $dir) {
      $tid = $git->get_id_by_path($home, $project, $cid, $dir, "tree");
    }
    else {
      $tid = $commit->{tree};
    }
  }
  die 404, "No such tree" unless defined $tid;

  my @entries = ();
  my $show_sizes = 0;
  {
    local $/ = "\0";
    open my $fd, "-|", $git->git($home, $project), "ls-tree", '-z',
      ($show_sizes ? '-l' : ()), $tid
      or die 500, "Open git-ls-tree failed";
    @entries = map { chomp; $_ } <$fd>;
    close $fd
      or die 404, "Reading tree failed";
  }
  
  my @trees;
  for my $line (@entries) {
    my %tree = $git->parse_ls_tree_line($line, -z => 1, -l => $show_sizes);
    $tree{mode_str} = $git->_mode_str($tree{mode});
    push @trees, \%tree;
  }

  $self->render(
    home => $home,
    project => $project,
    dir => $dir,
    cid => $cid,
    tid => $tid,
    commit => $commit,
    trees => \@trees
  );
}

sub snapshot {
  my $self = shift;

  # Validation
  my $raw_params = _parse_params($self);
  my $rule = [
    home => ['not_blank'],
    project => ['not_blank'],
    cid => {require => 0 } => ['not_blank'],
  ];
  my $vresult = $self->app->validator->validate($raw_params, $rule);
  die unless $vresult->is_ok;
  my $params = $vresult->data;
  my $home = $params->{home};
  my $project = $params->{project};
  my $cid = $params->{cid};
  $cid = "HEAD" unless defined $cid;
  
  # Git
  my $git = $self->app->git;

  # Object type
  my $type = $git->get_object_type($home, $project, "$cid^{}");
  if (!$type) { die 404, 'Object does not exist' }
  elsif ($type eq 'blob') { die 400, 'Object is not a tree-ish' }

  my ($name, $prefix) = $git->snapshot_name($home, $project, $cid);
  my $file = "$name.tar.gz";
  my $cmd = _quote_command(
    $git->git($home, $project), 'archive', "--format=tar", "--prefix=$prefix/", $cid
  );
  $cmd .= ' | ' . _quote_command('gzip', '-n');

  $file =~ s/(["\\])/\\$1/g;

  open my $fd, "-|", $cmd
    or die 500, "Execute git-archive failed";
  
  # Write chunk
  $self->res->headers->content_type('application/x-tar');
  $self->res->headers->content_disposition(qq/attachment; filename="$file"/);
  my $cb;
  $cb = sub {
    my $c = shift;
    my $size = 500 * 1024;
    my $length = sysread($fd, my $buffer, $size);
    unless (defined $length) {
      close $fd;
      undef $cb;
      return;
    }
    $c->write_chunk($buffer, $cb);
  };
  $self->$cb;
}

sub tag {
  my $self = shift;
  
  # Validation
  my $raw_params = _parse_params($self);
  my $rule = [
    home => ['not_blank'],
    project => ['not_blank'],
    id => ['not_blank']
  ];
  my $vresult = $self->app->validator->validate($raw_params, $rule);
  die unless $vresult->is_ok;
  my $params = $vresult->data;
  my $home = $params->{home};
  my $project = $params->{project};
  my $id = $params->{id};
  
  # Git
  my $git = $self->app->git;
  
  # Ref names
  my $tag  = $git->parse_tag($home, $project, $id);
  my %author_date = %$tag
    ? $git->parse_date($tag->{author_epoch}, $tag->{author_tz})
    : ();
  my $author_date = $git->_timestamp(\%author_date);
  $tag->{author_date} = $author_date;
  
  # Render
  $self->render(
    home => $home,
    project => $project,
    tag => $tag,
  );
}

sub tags {
  my $self = shift;
  
  # Validation
  my $raw_params = _parse_params($self);
  my $rule = [
    home => ['not_blank'],
    project => ['not_blank']
  ];
  my $vresult = $self->app->validator->validate($raw_params, $rule);
  die unless $vresult->is_ok;
  my $params = $vresult->data;
  my $home = $params->{home};
  my $project = $params->{project};
  
  # Git
  my $git = $self->app->git;
  
  # Ref names
  my $tags  = $git->get_tags($home, $project);
  
  # Render
  $self->render(
    home => $home,
    project => $project,
    tags => $tags,
  );
}

sub heads {
  my $self = shift;
  
  # Validation
  my $raw_params = _parse_params($self);
  my $rule = [
    home => ['not_blank'],
    project => ['not_blank']
  ];
  my $vresult = $self->app->validator->validate($raw_params, $rule);
  die unless $vresult->is_ok;
  my $params = $vresult->data;
  my $home = $params->{home};
  my $project = $params->{project};
  
  # Git
  my $git = $self->app->git;
  
  # Ref names
  my $heads  = $git->get_heads($home, $project);
  
  # Render
  $self->render(
    home => $home,
    project => $project,
    heads => $heads,
  );
}

sub blob {
  my $self = shift;

  # Validation
  my $raw_params = _parse_params($self);
  my $rule = [
    home => ['not_blank'],
    project => ['not_blank'],
    cid => ['not_blank'],
    file => ['not_blank']
  ];
  my $vresult = $self->app->validator->validate($raw_params, $rule);
  die unless $vresult->is_ok;
  my $params = $vresult->data;
  my $home = $params->{home};
  my $project = $params->{project};
  my $cid = $params->{cid};
  my $file = $params->{file};
  
  # Git
  my $git = $self->app->git;

  # Blob id
  my $bid = $git->get_id_by_path($home, $project, $cid, $file, "blob")
    or die "Cannot find file";
  
  # Blob
  my @git_cat_file = (
    $git->git($home, $project),
    "cat-file",
    "blob",
    $bid
  );
  open my $fd, "-|", @git_cat_file
    or die "Couldn't cat $file, $bid";
  
  my $mimetype = $git->blob_mimetype($fd, $file);

  # Redirect to blob plane
  if ($mimetype !~ m!^(?:text/|image/(?:gif|png|jpeg)$)! && -B $fd) {
    close $fd;
    my $url = $self->url_for('/blob_plain')->query([home => $home, project => $project,
      cid => $cid, file => $file]);
    return $self->refirect_to($url);
  }
  
  # Commit
  my %commit = $git->parse_commit($home, $project, $cid);

  my @lines;
  while (my $line = <$fd>) {
    chomp $line;
    $line = $git->_untabify($line);
    push @lines, $line;
  }
  
  $self->render(
    home => $home,
    project => $project,
    cid => $cid,
    bid => $bid,
    file => $file,
    commit => \%commit,
    lines => \@lines
  );
}

sub blob_plain {
  my $self = shift;

  # Validation
  my $raw_params = _parse_params($self);
  my $rule = [
    home => ['not_blank'],
    project => ['not_blank'],
    cid => ['not_blank'],
    file => ['not_blank']
  ];
  my $vresult = $self->app->validator->validate($raw_params, $rule);
  die unless $vresult->is_ok;
  my $params = $vresult->data;
  my $home = $params->{home};
  my $project = $params->{project};
  my $cid = $params->{cid};
  my $file = $params->{file};

  # Git
  my $git = $self->app->git;

  # Blob id
  my $bid = $git->get_id_by_path($home, $project, $cid, $file, "blob")
    or die "Cannot find file";
  open my $fd, "-|", $git->git($home, $project), "cat-file", "blob", $bid
    or die "Open git-cat-file blob '$bid' failed";

  # content-type (can include charset)
  my $type = $git->blob_contenttype($fd, $file);

  # "save as" filename, even when no $file is given
  my $save_as = "$cid";
  if (defined $file) {
    $save_as = $file;
  } elsif ($type =~ m/^text\//) {
    $save_as .= '.txt';
  }

  my $sandbox = $self->prevent_xss &&
    $type !~ m!^(?:text/[a-z]+|image/(?:gif|png|jpeg))(?:[ ;]|$)!;

  # serve text/* as text/plain
  if ($self->prevent_xss &&
      ($type =~ m!^text/[a-z]+\b(.*)$! ||
       ($type =~ m!^[a-z]+/[a-z]\+xml\b(.*)$! && -T $fd))) {
    my $rest = $1;
    $rest = defined $rest ? $rest : '';
    $type = "text/plain$rest";
  }
  
  my $content = do { local $/ = undef; <$fd> };
  my $content_disposition = $sandbox ? 'attachment' : 'inline';
  $content_disposition .= "; filename=$save_as";
  $self->res->headers->content_disposition($content_disposition);
  $self->res->headers->content_type($type);
  $self->render_data($content);

}

sub blobdiff {
  my $self = shift;

  # Validation
  my $raw_params = _parse_params($self);
  my $rule = [
    home => ['not_blank'],
    project => ['not_blank'],
    cid => ['any'],
    file => ['any'],
    from_cid => ['any'],
  ];
  my $vresult = $self->app->validator->validate($raw_params, $rule);
  die unless $vresult->is_ok;
  my $params = $vresult->data;
  my $home = $params->{home};
  my $project = $params->{project};
  my $cid = $params->{cid};
  my $file = $params->{file};
  my $from_cid = $params->{from_cid};
  my $from_file = $params->{from_file};

  # Git
  my $git = $self->app->git;
  
  my $suffix = $self->param('suffix') || '';
  my $plain;
  if ($suffix) {
    if ($suffix eq '_plain') { $plain = 1 }
    else { return $self->render('not_found') }
  }
  else { $plain = 0 }

  my $fd;
  my @difftree;
  my %diffinfo;
  
  my $bid;
  my $from_bid;

  if (defined $cid && defined $from_cid) {
    if (defined $file) {
      # git diff tree
      my @git_diff_tree = ($git->git($home, $project), "diff-tree", '-r',
        @{$self->diff_opts}, $from_cid, $cid, "--",
        (defined $from_file ? $from_file : ()), $file
      );
      
      open $fd, "-|", @git_diff_tree
        or die 500, "Open git-diff-tree failed";
      @difftree = map { chomp; $_ } <$fd>;
      close $fd
        or die 404, "Reading git-diff-tree failed";
      @difftree
        or die 404, "Blob diff not found";

    } elsif (defined $bid && $bid =~ /[0-9a-fA-F]{40}/) {

      # read filtered raw output
      open $fd, "-|", $git->git($home, $project), "diff-tree", '-r', @{$self->diff_opts},
          $from_cid, $cid, "--"
        or die "Open git-diff-tree failed";
      @difftree =
        grep { /^:[0-7]{6} [0-7]{6} [0-9a-fA-F]{40} $bid/ }
        map { chomp; $_ } <$fd>;
      close $fd
        or die("Reading git-diff-tree failed");
      @difftree
        or die("Blob diff not found");

    } else {
      die "Missing one of the blob diff parameters";
    }

    if (@difftree > 1) {
      die "Ambiguous blob diff specification";
    }

    %diffinfo = $git->parse_difftree_raw_line($difftree[0]);
    $from_file ||= $diffinfo{'from_file'} || $file;
    $file   ||= $diffinfo{'to_file'};

    $from_bid ||= $diffinfo{'from_id'};
    $bid        ||= $diffinfo{'to_id'};

    # open patch output
    open $fd, "-|", $git->git($home, $project), "diff-tree", '-r', @{$self->diff_opts},
      '-p', (!$plain ? "--full-index" : ()),
      $from_cid, $cid,
      "--", (defined $from_file ? $from_file : ()), $file
      or die_error(500, "Open git-diff-tree failed");
  }
  
  if (!%diffinfo) {
    die '404 Not Found', "Missing one of the blob diff parameters";
  }
  
  my $commit = $git->parse_commit($home, $project, $cid);

  if ($plain) {
    my $content = do { local $/; <$fd> };
    my $content_disposition .= "inline; filename=$file";
    $self->res->headers->content_disposition($content_disposition);
    $self->res->headers->content_type("text/plain");
    $self->render_data($content);
  }
  else {
    # patch
    my @lines;
    while (my $line = <$fd>) {
      chomp $line;
      my $class;
      
      if ($line =~ /^diff \-\-git /) { $class = 'diff header' }
      elsif ($line =~ /^index /) { $class = 'diff extended_header' }
      elsif ($line =~ /^\+/) { $class = 'diff to_file' }
      elsif ($line =~ /^\-/) { $class = 'diff from_file' }
      elsif ($line =~ /^\@\@/) { $class = 'diff chunk_header' }
      else { $class = 'diff' }
      push @lines, {value => $line, class => $class};
    }
    close $fd;

    $self->render(
      '/blobdiff',
      home => $home,
      project => $project,
      cid => $cid,
      from_cid => $from_cid,
      file => $file,
      commit => $commit,
      diffinfo => \%diffinfo,
      lines => \@lines
    );
  }
}

sub _log {
  my ($self, %opt) = @_;

  my $short = $opt{short};

  # Validation
  my $raw_params = _parse_params($self);
  my $rule = [
    home => ['not_blank'],
    project => ['not_blank'],
    page => {require => 0} => ['int'],
    base_cid => {require => 0} => ['any']
  ];
  my $vresult = $self->app->validator->validate($raw_params, $rule);
  die unless $vresult->is_ok;
  my $params = $vresult->data;
  my $home = $params->{home};
  my $project = $params->{project};
  my $base_cid = defined $params->{base_cid}
    ? $params->{base_cid}
    :"HEAD";
  my $page = $params->{page} || 0;
  $page = 0 if $page < 0;
  
  # Git
  my $git = $self->app->git;
  
  # Base commit
  my $base_commit = $git->parse_commit($home, $project, $base_cid);
  
  # Commits
  my $page_count = $short ? 50 : 20;
  my $commits = $git->parse_commits($home, $project, $base_commit->{id}, $page_count, $page_count * $page);
  
  # Ref names
  my $ref_names = {};
  my $tags  = $git->get_tags($home, $project);
  $ref_names->{tag}{$_->{id}} = $_->{name} for @$tags;
  my $heads = $git->get_heads($home, $project);
  $ref_names->{head}{$_->{id}} = $_->{name} for @$heads;

  # Render
  my $template = $short ? 'shortlog' : 'log';
  $self->render(
    $template,
    home => $home,
    project => $project,
    base_cid => $base_cid,
    commits => $commits,
    ref_names => $ref_names,
    page => $page,
    page_count => $page_count
  );
};

sub _parse_params {
  my $c = shift;
  my $params = {map { $_ => scalar $c->param($_) } $c->param};
  return $params;
}

sub _quote_command {
  return join(' ',
    map { my $a = $_; $a =~ s/(['!])/'\\$1'/g; "'$a'" } @_ );
}

1;
