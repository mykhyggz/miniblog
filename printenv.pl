#!/usr/bin/perl
##
##  printenv -- demo CGI program which just prints its environment
##

use Cwd;


print "Content-type: text/plain\n\n";

print cwd()."\n";
foreach $var (sort(keys(%ENV))) {
    $val = $ENV{$var};
    $val =~ s|\n|\\n|g;
    $val =~ s|"|\\"|g;
    print "${var}=\"${val}\"\n";
}

