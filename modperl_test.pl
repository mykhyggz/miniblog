
use Data::Dumper;
my $r = Apache2::RequestUtil->request();
$r->content_type('text/plain');
print Dumper(\%ENV);
