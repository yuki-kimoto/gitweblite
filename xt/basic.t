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
  ->content_like(qr#<span class="head" title="heads/master">\s*<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog/master">\s*master\s*</a>\s*</span>#)
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

;
