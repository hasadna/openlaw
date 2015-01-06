#!/usr/bin/perl -w

use strict;
no strict 'refs';
use English;
use utf8;
use Data::Dumper;
use HTML::Parser;
use HTML::TreeBuilder::XPath;
use IO::HTML;
use Getopt::Long;


my $what = 0;
GetOptions(
	"dump" => sub { $what = 0 },
	"print" => sub { $what = 1 },
	"short" => sub { $what = 2 },
	"url" => sub { $what = 3 },
) or die $!;

my $page = $ARGV[0];
my $id;
my ($tree, @trees);
my (@table, @lol);

if ($page =~ /^\d+$/) {
	$page = "http://main.knesset.gov.il/Activity/Legislation/Laws/Pages/LawPrimary.aspx?t=lawlaws&st=lawlaws&lawitemid=$page";
}

binmode STDOUT, ":utf8";


while ($page) {
	print STDERR "Reading HTML file...\n";
	if (-f $page) {
		$tree = HTML::TreeBuilder::XPath->new_from_file(html_file($page));
	} else {
		$tree = HTML::TreeBuilder::XPath->new_from_url($page);
	}
	push @trees, $tree;
	
	my @loc_table = $tree->findnodes('//table[@class = "rgMasterTable"]//tr');
	
	my $loc_id = $tree->findnodes('//form[@name = "aspnetForm"]')->[0];
	($loc_id) = ($loc_id->attr('action') =~ m/lawitemid=(\d+)/);
	$id ||= $loc_id;
	
	my $nextpage = $tree->findnodes('//td[@class = "LawBottomNav"]/a[contains(@id, "_aNextPage")]')->[0] || '';
	$nextpage &&= $nextpage->attr('href');
	if ($nextpage) {
		$page = "http://main.knesset.gov.il$nextpage";
	} else {
		$page = '';
	}
	
	# Remove first row and push into @table;
	shift @loc_table;
	@table = (@table, @loc_table);
}

foreach my $node (@table) {
    my @list = $node->findnodes('td');
    shift @list;
    my $url = pop @list;
    my $lawid = $list[0]->findnodes('a')->[0];
    $lawid &&= $lawid->attr('href'); $lawid ||= '';
    $lawid = $1 if ($lawid =~ m/lawitemid=(\d+)/);
    map { $_ = $_->as_text(); } @list;
    $url = $url->findnodes('a')->[0];
    $url &&= $url->attr('href'); $url ||= '';
    $url =~ s|/?\\|/|g;
    $url =~ s/\.PDF$/.pdf/;
    push @list, $lawid, $url;
    grep(s/^[ \t\xA0]*(.*?)[ \t\xA0]*$/$1/g, @list);
    push @lol, [@list];
}

# # Sort array in lexicographical order of [booklet, page, lawid].
# @lol = sort { $a->[2] <=> $b->[2] || $a->[3] <=> $b->[3] || $a->[5] <=> $b->[5] } @lol;
# Sort array in lexicographical order of [booklet, page, NAME] (lawid is not monotonic).
@lol = grep { $_->[2] =~ /\d+/ } @lol;
@lol = sort { $a->[2] <=> $b->[2] || $a->[3] <=> $b->[3] || $a->[0] cmp $b->[0] } @lol;

foreach my $list (@lol) {
	print_fix(@$list) if ($what>=1);
	print_line(@$list) if ($what==0);
}

print_fix() if ($what>=1);

# Cleanups
$_->delete() for (@trees);

exit 0;

#-------------------------------------------------------------------------------

my ($last_type, $last_year, $last_id);
my $law_name;
my $first_run;

sub print_line {
	pop @_;
	print join('|',@_) . "\n";
}

sub print_fix {
	$first_run = (!defined($first_run));
	
	my ($name, $type, $booklet, $page, $date, $lawid, $url) = @_;
	my $year = '';
	
	if (!defined($name)) {
		print ".\n" if (!$first_run);
		return;
	}

	return if ($lawid ne '' && $last_id && $lawid eq $last_id);
	$last_id = $lawid if ($lawid);
	
	$type =~ s/ה?(.)\S+ ?/$1/g; $type =~ s/(?=.$)/"/;
	$name =~ s/,? *ה?(תש.?".)-\d{4}// and $year = $1;
	$year = poorman_hebrewyear($date,$page);
	
	$name =~ s/ {2,}/ /g;
	$name =~ s/ *\(חוק מקורי\)//;
	$law_name = $name if ($first_run);
	
	$name =~ s/ (ב|של |)$law_name$//;
	$name =~ s/^תיקון טעות.*/ת"ט/;
	$name =~ s/\((מס' \d\S*?)\)/(תיקון $1)/;
	$name =~ s/^(?:חוק לתיקון |)$law_name \((.*?)\)/ $1/;
	$name =~ s/חוק לתיקון פקודת/תיקון לפקודת/;
	$name =~ s/^(?:חוק לתיקון |תיקון ל|)(\S.*?)\s\((תי?קון .*?)\)/$2 ל$1/;
	$name =~ s/ *(.*?) */$1/;
	
	$url =~ s/.*?\/(\d+)_lsr_(\d+).pdf/$1:$2/ if ($what==2);
	
	if ($last_type && $type eq $last_type) { $type = ''; } else { $last_type = $type; }
	if ($last_year && $year eq $last_year) { $year = ''; } else { $last_year = $year; }
	
	print ", " if (!$year);
	print "; " if ($year and !$type);
	print ".\n" if ($year and $type and !$first_run);
	
	print "((";
	print "$type " if ($type);
	print "$year, " if ($year);
	print "$page|$name";
	print "|$url" if ($url and $what>=2);
	print "))";
}


sub poorman_hebrewyear {
	my $date = shift;
	my $page = shift // 500;
	my $year = ''; my $mmdd = '';
	
	# Convert date to YYYYMMDD
	$date =~ s/.*?(\d{1,2})(.)(\d{1,2})\2(\d{4}).*?/sprintf("%04d%02d%02d",$4,$3,$1)/e || return '';
	$year = $4; $mmdd = substr($date,4,4);
	return $year if ($date < "19480514");
	$year += 3760;
	# Assume new year starts between YYYY0901 and YYYY1015
	$year++ if (($mmdd > "0900" and $mmdd <= "1015" and $page<200) or ($mmdd > "1015"));
	$year =~ /(\d)(\d)(\d)(\d)$/;
	$year = (qw|- ק ר ש ת תק תר תש תת תתק|)[$2] . (qw|- י כ ל מ נ ס ע פ צ|)[$3] . (qw|- א ב ג ד ה ו ז ח ט|)[$4];
	$year =~ s/-//g;
	$year =~ s/י([הו])/"ט" . chr(ord($1)+1)/e;  # Handle טו and טז.
	$year =~ s/([כמנפצ])$/chr(ord($1)-1)/e;     # Ending-form is one char before regular-form.
	$year =~ s/(?=.$)/"/;
	return $year;
}
