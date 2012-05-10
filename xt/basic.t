use strict;
use warnings;
use utf8;

use Test::More 'no_plan';

use FindBin;
use lib "$FindBin::Bin/../lib";
use Gitweblite;

use Test::Mojo;

my $app = Gitweblite->new;
my $t = Test::Mojo->new($app);

# Home
$t->get_ok('/')
  ->content_like(qr/Gitweb Lite/)
  ->content_like(qr/Home Directory/)
  ->content_like(qr#/home/kimoto/labo/#)
  ->content_like(qr#href="/home/kimoto/labo/projects"#)
;

# Projects
my $home = '/home/kimoto/labo';
$t->get_ok("$home/projects")
  # Page title
  ->content_like(qr/Projects/)
  # Home directory
  ->content_like(qr#<a href="/">home</a> &gt;\s*<a href="/home/kimoto/labo/projects">/home/kimoto/labo</a>#)
  # Project link
  ->content_like(qr#<a class="list" href="/home/kimoto/labo/gitweblite_devrep.git/summary">\s+gitweblite_devrep.git\s+</a>#)
  # Description link
  ->content_like(qr#<a class="list" title="Test Repository\s*"\s*href="/home/kimoto/labo/gitweblite_devrep.git/summary">\s*Test Repository\s*</a>#)
  # Owner
  ->content_like(qr#<td><i>kimoto</i></td>#)
  # Content links
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/summary">summary</a>#)
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog">shortlog</a>#)
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/log">log</a>#)
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree">#)
;

# Summary
my $project = "$home/gitweblite_devrep.git";
my $git = $app->git;
my $head = $git->get_head_id($project);
my $tag_t21 = $git->get_tag($project, 't21');
$t->get_ok("$project/summary")
  # Page navi
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog/$head">Shortlog</a>#)
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/log/$head">Log</a>#)
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commit/$head">\s*Commit\s*</a>#)
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commitdiff/$head">Commitdiff</a>#)
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/$head">Tree</a>#)
  # Description
  ->content_like(qr#<tr id="metadata_desc"><td><b>Description:</b></td><td>Test Repository\s*</td></tr>#)
  # Owner
  ->content_like(qr#<tr id="metadata_owner"><td><b>Owner:</b></td><td>kimoto</td></tr>#)
  # Ripository URL
  ->content_like(qr#http://somerep.git\s*<br />\s*git://somerep.git\s*<br />#)
  # Branch
  ->content_like(qr#<span class="head" title="heads/master">\s*<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog/refs/heads/master">\s*master\s*</a>\s*</span>#)
  # Shorlog comment link
  ->content_like(qr#<a class="list subject" href=\s*"/home/kimoto/labo/gitweblite_devrep.git/commit/$head"\s* >\s*日本語の内容を追加\s*</a>#)
  # Shortlog commit link
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commit/$head">\s*commit\s*</a>#)
  # Shortlog commitdiff link
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commitdiff/$head">\s*commitdiff\s*</a>#)
  # Shortlog tree link
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/$head">\s*tree\s*</a>#)
  # Shortlog snapshot link
  ->content_like(qr#<a title="in format: tar.gz" rel="nofollow" href=\s*"/home/kimoto/labo/gitweblite_devrep.git/snapshot/$head">\s*snapshot\s*</a>#)
  # Tag name link
  ->content_like(qr#<a class="list name" href=\s*"/home/kimoto/labo/gitweblite_devrep.git/commit/$tag_t21->{refid}"\s*>\s*t10\s*</a>#)
  # Tag comment link
  ->content_like(qr#<a class="list subject" href=\s*"/home/kimoto/labo/gitweblite_devrep.git/tag/$tag_t21->{id}"\s*>\s*t21\s*</a>#)
  # Tag shortlog link
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog/refs/tags/t21"\s*>\s*shortlog\s*</a>#)  # Tag log link
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/log/refs/tags/t21">\s*log\s*</a>#)
  # Tags link
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tags">\s*...\s*</a>#)
  # Head name link
  ->content_like(qr#<a class="list name" href="/home/kimoto/labo/gitweblite_devrep.git/log/refs/heads/b10">\s*b10\s*</a>#)
  # Head shortlog link
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog/refs/heads/b10">\s*shortlog\s*</a>#)
  # Head log link
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/log/refs/heads/b10">\s*log\s*</a>#)
  # Head tree link
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/b10">\s*tree\s*</a>#)
  # Heads link
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/heads">\s*...\s*</a>#)
;

# Commit
my $id = '6d71d9bc1ee3bd1c96a559109244c1fe745045de';
my $commit = $git->parse_commit($project, $id);
my $parent = $commit->{parent};
my $parent_short = substr($parent, 0, 7);
$t->get_ok("$project/commit/$id")
  # Parent
  ->content_like(qr#parent:\s*<a href="/home/kimoto/labo/gitweblite_devrep.git/commit/$parent">\s*$parent_short\s*</a>#)
  # Title
  ->content_like(qr#<a class="title" href="/home/kimoto/labo/gitweblite_devrep.git/commitdiff/$id">\s*日本語の内容を追加\s*</a>#)
  # Head link
  ->content_like(qr#<span class="head" title="heads/b10">\s*<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog/refs/heads/b10">\s*b10\s*</a>\s*</span>#)
  # Tag link
  ->content_like(qr#<span class="tag" title="tags/t10">\s*<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog/refs/tags/t10">\s*t10\s*</a>\s*</span>#)
  # Author
  ->content_like(qr#<td>author</td>\s*<td>Yuki Kimoto &lt;kimoto.yuki\@gmail.com&gt;</td>#)
  # Committer
  ->content_like(qr#<td>committer</td>\s*<td>Yuki Kimoto &lt;kimoto.yuki\@gmail.com&gt;</td>#)
  # Commit
  ->content_like(qr#<td>commit</td>\s*<td class="sha1">$id</td>#)
  # Tree commit id link
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/$id">\s*tree\s*</a>#)
  # Tree link
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/$id">\s*tree\s*</a>#)
  # Snapshot link
  ->content_like(qr#<a title="in format: tar.gz" rel="nofollow"\s*href="/home/kimoto/labo/gitweblite_devrep.git/snapshot/$id">\s*snapshot\s*</a>#)
  # Parent commit id link
  ->content_like(qr#<a class="list" href="/home/kimoto/labo/gitweblite_devrep.git/commit/$parent">\s*$parent\s*</a>#)
  # Parent commit link
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commit/$parent">\s*commit\s*</a>#)
;
