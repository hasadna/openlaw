#!/usr/bin/perl

use warnings;
no if ($]>=5.018), warnings => 'experimental';
use strict;
no strict 'refs';
use utf8;
use English;
use Encode;
use Getopt::Long;
use IPC::Run 'run';

binmode STDIN, "utf8";
binmode STDOUT, "utf8";
binmode STDERR, "utf8";

my $raw = 1;
my $brackets = 1;

GetOptions(
	"raw" => \$raw,
	"brackets" => sub { $brackets = 0; },
) or die("Error in command line arguments\n");

local $/;
$_ = <>;
$_ = cleanup($_);

my $fix_sig = 'תי?קו(?:ן|ים)';
my $num_sig = '\d(?:[^ ,.:;"\n\[\]()]+|\([^ ,.:;"\n\[\]()]+\))*+';
my $ext_sig = 'ה?(?:(ראשו[נן]ה?|שניי?ה?|שלישית?|רביעית?|חמישית?|שי?שית?|שביעית?|שמינית?|תשיעית?|עשירית?|[א-י][\' ]|[טי]"[א-ט]|\d+[א-ת])(\d*))';
my $law_sig = 'ו?ש?[בהלמ]?(?:חוק|פקוד[הת]|תקנות|צו)';

# ignore /^[=:@<]/

s/^[\x{05C1}\x{05C2}]+//gm; # Strange typo in reshumot PDF

s/(?:\(תיקון מס'|תיקון \(מס') (\d+)\) (תש.?".)-\d{4}/(תיקון: $2#$1)/g;
s/\n? *([\(\[])(תי?קון|תיקונים):?+ *+(?!מס)/ $1תיקון: /g;
# s/(?<=\(תיקון: )(\S+)\) \(תיקון: (\S+)\)/$1, $2)/g;
# s/\) \(תיקון:\s*/, /g;

s/^("?חלק ($num_sig|$ext_sig) *([:,-].*|))$/\n= $1 =\n/gm;
s/^("?(פרק|תוספת) ($num_sig|$ext_sig) *([:,-].*|))$/\n== $1 ==\n/gm;
s/^("?סימן ($num_sig|$ext_sig) *([:,-].*|))$/\n=== $1 ===\n/gm;

if ($raw) {
	s/^(.+)\n(\d+|\*)\n/$2 $1\n/gm;
	# s/^(\d+[,;.]?)\n($law_sig.*)/$2 $1/gm;
	s/^(\d+[,;.]?.*?)\n(.*?\d{4}( \[.*?\])?)$/$2 $1/gm;
}

# Should swap chapter title and numeral
s/^("?\(\S{1,4}?\))\n("?\(\S{1,4}?\))/$1 $2/gm;
# while (s/\n(.*)\n("?\(.{1,2}\)|\*|[0-9]|[1-9].?\.)\n/\n$2 $1\n/g) {}
s/^(.+)\n("?\(\S{1,4}?\))\n(?!\()/$2 $1\n/gm;
s/^(.+[^".;\n])\n("?\d\S*?\.)\n/$2 $1\n/gm;

# print $_; exit;

s/^([0-9=\@:].*)$/$1 /gm; # Disallow concatination on certain prefixes
s/([א-ת\-\,])\n([א-ת\-])/$1 $2/gm;


s/^(?:\n?@ *|)(\d[^. \n]*\.)(\D.*)$/"\n@ $1 " . fix_description($2)/gme;
s/^([^\.=\n]+)\n\n(@ \d.*\. )/\n\n$2 $1 /gm;
s/^("?\([^)]{1,4}\))/: $1/gm;
s/^(@.*?)\n([^:]+)$/$1\n: $2/gm;

if ($raw) {
	while (s/^(.{5,20}?[^"=.;\n)])\n{2,3}(@ \d.*?\.) /\n\n$2 $1 /gm) {}
}

s/^(:+) *(\([^)\n]*\)[.;])$/$1 (($2))/gm;
s/^(:+ \([^ )\n]+\)) (\([^)\n]*\)[.;])$/$1 (($2))/gm;
s/ {2,}/ /g;


if ($brackets) {
	s/(?<!\[)(ו?ש?[בהלמ]?(סעיף|סעיפים|תקנה|תקנות) $num_sig)(?!\])/[[$1]]/g;
	pos = 0;
	my $repeat = 0;
	while ($repeat || m/\[\[(.*?)\]\]/gc) {
		$repeat = 0;
		next if /\G[,; ]*\[\[/;
		my $pos = $+[1];
		pos = $pos;
		# m/(.{0,20})\G(.{0,20})/; print STDERR "POS is $pos\t ... $1<-|->$2 ...\n";
		
		0 	|| s/\G\]\], ($num_sig)/]], [[$1]]/
			|| s/\G\]\](,?(( ו-| או | עד |)\([א-ת\d]+\))+)/$1]]/
			|| s/\G\]\]( עד $num_sig| (?:ו-|או) \(\d\S*?\))/$1]]/
			|| s/\G\]\] ((?:ו-|או )$num_sig)(?!\])/]] [[$1]]/
			|| next;
		
		pos = $pos;
		# m/(.{0,20})\G(.{0,20})/; print STDERR "\t\t ... $1<-|->$2 ...\n";
		
		$repeat = 1;
		m/(.*?)\]\]/gc;
	}
	
	s/(?<!\[)(ו?ש?[בהלמ]?(פרק|פרקים|סימן|סימנים|תוספת) ה?(ז[הו]|$num_sig|$ext_sig)[^ ,.:;\n\[\]]{0,8}+)(?![\]:])/[[$1]]/g;
	# s/(?<!\[)(ו?ש?[בהלמ]?(תוספת))\b(?!\])/[[$1]]/g;
	s/(?<!\[)($law_sig [^;.\n]{1,100}?(, |-)\d{4})(?!\])/[[$1]]/g;
	s/\]\]( \[(נוסח חדש|נוסח משולב)\])/$1]]/g;
	s/\]\] \[\[(?=$law_sig)/ /g;
	s/\[\[($law_sig [^\[\]].*?) ($law_sig[^\[\]].*)\]\]/$1 [[$2]]/g;

	s/\[\[([^\[\]]*+)\[\[(.*?)\]\](.*?)\]\]/[[$1$2$3]]/g;
	s/^(=.*)$/remove_brakets($1)/gme;
}

if (/^\[*(חוק|פקודת|תקנות)\b/s) {
	s/^(?:\<שם\>|) *(.*)\n/"<שם> ". remove_brakets($1) . "\n"/se;
	s/^(.*?\n)/$1\n<מקור> ...\n/s if (!/<מקור>/);
}

s/\n*(.*?)\n*$/$1\n/s;
s/\n{3,}/\n\n/g;
s/ +$//mg;

print $_;

exit;
1;


sub fix_description {
	my $_ = shift;
	s/(?<=\()(תי?קון|תיקונים):? */תיקון: /;
	s/ה(תש.?".?)/$1/g;
	s/(תש.?".) \(מס' (\d.*?)\)/$1-$2/g;
	while (s/(תש.?".)-(\d[^\,]*|),\s*\(מס' (\d.*?)\)/$1-$2, $1-$3/g) {};
	s/\[(תיקון: .*?)\]/($1)/;
	return $_;
}

sub remove_brakets {
	my $_ = shift;
	s/\[\[//;
	s/\]\]//;
	return $_;
}


sub cleanup {
	my $pwd = $0; $pwd =~ s/[^\/]*$//;
	my @cmd = ("$pwd/clear.pl");
	my $in = shift;
	my $out;
	run \@cmd, \$in, \$out, *STDERR;
	return decode_utf8($out);
}
