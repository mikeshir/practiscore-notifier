#!/usr/bin/perl -w

use strict;
use v5.10;
use English;

use WWW::Mechanize;
use HTML::TreeBuilder;
use Mail::Sendmail;

my $USER = $ENV{USER} or die 'USER is not set';
my $PASSWORD = $ENV{PASSWORD} or die 'PASSWORD is not set';
my $FROM = $ENV{FROM} or die 'FROM is not set';
my $TO = $ENV{TO} || $USER;
my $SITE = 'https://practiscore.com';
my $DB = $ENV{DB} || do { $PROGRAM_NAME =~ /(.*)\.\w+$/; "$1.csv" };
my $FORMAT_ERR = 'Looks like the HTML page format changed, time to update the script';

my %seen;
if(open(my $f, '<', $DB)) {
    %seen = map { (split(','))[0] => 1 } <$f>;
}

my $ua = new WWW::Mechanize(agent => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.1 Safari/605.1.15');
$ua->get("$SITE/login");
$ua->submit_form(fields => {username => $USER, password => $PASSWORD});
my $r = $ua->get("/dashboard/findevents");
my $root = HTML::TreeBuilder->new_from_content($r->decoded_content);
foreach my $tr (($root->find_by_attribute('id', 'findevents')->find_by_tag_name('table'))[1]->find_by_tag_name('tr')) {
    my @tds = $tr->find_by_tag_name('td') or next;
    my($a) = $tds[0]->find_by_tag_name('a');
    my $link = $a->attr('href');
    my($name) = $a->content_list;
    my($date) = $tds[1]->content_list;
    my $class = ($tds[2]->find_by_tag_name('i'))[0]->attr('class');
    $link && $name && $date && $class or die $FORMAT_ERR;
    next if($seen{$link});
    goto NOTIFY if($class =~ /text-success/);
    $class =~ /text-danger/ or die $FORMAT_ERR;
    my $r = $ua->get($link);
    my $root = HTML::TreeBuilder->new_from_content($r->decoded_content);
    my($div) = grep { $_->attr('class') && $_->attr('class') =~ /alert alert\-info/ } $root->find_by_tag_name('div') or die $FORMAT_ERR;
    my($msg) = ($div->find_by_tag_name('strong') || $div->find_by_tag_name('h4'))->content_list or die $FORMAT_ERR;
    next if($msg =~ /Registration opens .* from now/);
  NOTIFY:
    sendmail(
        From => $FROM,
        To => $TO,
        Subject => 'New match registration available: $name',
        Message => "$name on $date: $SITE/$link\n"
      ) or die "Couldn't send email";
    open(my $f, '>>', $DB) or die "Cannot create $DB: $OS_ERROR\n";
    my $timestamp = localtime();
    say $f "$link,$name,$date,$timestamp";
}
