package Kenterblogger;
use strict;
use warnings;

use DBI;
use CGI qw/:cgi/;
use Apache::Session::SQLite; 
# use Apache2::Const qw(:common);
use Digest::SHA qw/sha256_hex/;

use 5.12.0;

no warnings 'redefine';

my $r = shift;
my $cgi = CGI->new( $r );
my $args = $cgi->Vars;

my $myurl='http://localhost/cgi-perl/session_test.pl';
my $realpath = '/var/www/localhost/perl/storage';

$r->content_type( 'text/html');

my $method = $r->method(); 

if ($method eq 'GET'){

# check for query string ?Login or something... 
my $query = join '', keys %$args;
    my $reply = <<"EOF";
<html><head><title>LogIn</title></head><body>
<h3>Login Here</h3>
<p>$query</p>
<form action="http://localhost/cgi-perl/session_test.pl" method="post">
Username: <input type="text" name="username">
Password: <input type="password" name="password"> 
<input type="submit" value="Login">
</form></body></html> 
EOF
    print $reply;
} # GET

elsif ($method eq 'POST') { 
    
    if (my $session_id=$args->{session_id}){ 
        # get our old session back, maybe
        my %session; 
        tie %session, 'Apache::Session::SQLite', $session_id, 
     { DataSource => "dbi:SQLite:/var/www/localhost/perl/storage/sessions.db" }; 
        if ($session{is_logged_in}){ 
            if ($args->{action} eq 'Logout') {
                $session{is_logged_in}=0; 
                print <<"EOF";
<html><head><title>Logged Out</title>
<meta http-equiv="refresh" content="5; url=$myurl">
</head><body>
<h2>Logged Out!</h2>
</body>
EOF
            }
            else {
# the meat of it, logged in, now, what does user/admin do?
# get user data from DBI here... is this secure? Well, folks should log out... 
# if they don't want to be vulnerable to hijacked sessions, for now.
                my $dbh = DBI->connect("dbi:SQLite:/var/www/localhost/perl/storage/users.db","","",
{ sqlite_use_immediate_transaction => 1, RaiseError => 1, AutoCommit => 1  });
                my $sth=$dbh->prepare("select * from users where last_session_id=?");

                $sth->execute($session_id);
                my $user_data = $sth->fetchrow_hashref(); 
                my $sid_found = $user_data->{last_session_id};
                $session_id = $session{_session_id};
                my $ua = $r->headers_in->{'User-Agent'}; 
                print <<"EOF";
<html><head><title></title></head><body>
<p>hey, we made it!</p>
<!--p>Session ID from user record: $sid_found</p--> 
<!--p>Session ID: $session_id</p--> 
<p> User Agent : $ua </p> 
<p>this should be config options, if no config, I guess,
or a full admin page</p>
<h4>remember to log out!</h4>
<form action="http://localhost/cgi-perl/session_test.pl" method="post"> 
<input type="hidden" name="session_id" value="$session_id">
<input type="hidden" name="action" value="Logout">
<input type="submit" value="Logout">
</form></body></html> 
EOF
            }
        } # is_logged_in
        else{ 
            # session open, but not logged in? 
        }    
    } # session_id
    else { 
        # do login, no session yet
        my $user=$args->{username}; 
        my $pass=$args->{password};
        if (my ($user_data, $session) =check_password ( $user, $pass )){ 
            # we passed! Here's the "landing page" for admin, or user 
            my $session_id = $session->{_session_id};
           if ($user_data->{id} == 0){ 
            print <<EOF;
<html><head><title>ADMIN PAGE</title></head><body>
<p>Howdy, $user_data->{username}!</p> 
<p>Here is where we can go to different places, the landing page</p> 
<p>Reminder: Do we need Apache::DBI?</p> 
<p>Add users?</p>
<form action="http://localhost/cgi-perl/session_test.pl" method="post"> 
<input type="hidden" name="session_id" value="$session_id">
<input type="hidden" name="action" value="AddUsers">
<input type="submit" value="Add Users">
</form></body></html> 
EOF
        }
        else {
# user view, nothing here, really, but 'edit' and 'add' stuff...
            print <<EOF;
<html><head><title>logged in!</title></head><body>
<p>Howdy, $user_data->{username}!</p> 
<p>Here is where we can go to different places, the landing page</p> 
<p>Reminder: Do we need Apache::DBI?</p> 
<form action="http://localhost/cgi-perl/session_test.pl" method="post"> 
<input type="hidden" name="session_id" value="$session_id">
<input type="hidden" name="action" value="">
<input type="submit" value="go to site">
</form></body></html> 
EOF
        }
        }
        else { #password failed!
        }
    } # no session ID
} # POST

sub check_password {
    my ($user_name, $pass_given) = @_; 
    my $dbh = DBI->connect("dbi:SQLite:/var/www/localhost/perl/storage/users.db","","", { sqlite_use_immediate_transaction => 1, RaiseError => 1, AutoCommit => 1  });
    my $sth=$dbh->prepare("select * from users where username=?");
    $sth->execute($user_name);
    my $user_data = $sth->fetchrow_hashref();
    my $hash_returned = $user_data->{password};
    my $user_id = $user_data->{id}; 
    my $session_id = ( $user_data->{last_session_id} || undef );

    if (! $hash_returned){ 
# user has no password stored, get one in there 
	if ($pass_given){
	#don't pass '$r'
	  if  (make_password( $user_id, $pass_given, $dbh)){
print <<"EOF";
<html><head><meta http-equiv="refresh"
      content="5; url=/perl/session_test.pl">
</head><body>
<p> $user_name has a password! Redirecting to login...</p>
<p>ID: $user_data->{id}</p>
<p>PWD: $user_data->{password}</p>
</body></html>
EOF

		};
	}
	else {
# user_id is probably wrong...
	print 'Content-Type: text/html; charset=UTF-8', "\n\n"; 
	print <<"EOF";
<html><head><title>Set Admin Password</title></head><body>
<p>$user_name, you have an empty password. This will not do.</p>
<form action="http://localhost/cgi-perl/session_test.pl" method="post">
Password: <input type="password" name="password" method="post"> 
<input type="hidden" value="$user_id">
<input type="submit" value="Set Password">
</form></body></html> 
EOF
    }
}
# we have a password to match
else {
    my ($salt,$hash_tomatch) = split ':', $hash_returned;
    my $sha_hash = sha256_hex($pass_given, "{$salt}"); 
    if ($sha_hash eq $hash_tomatch){ 
	    my %session; 
            #make a fresh session for a first-time visitor, or maybe re-open
eval {            tie %session, 'Apache::Session::SQLite', $session_id, 
     { DataSource => 'dbi:SQLite:/var/www/localhost/perl/storage/sessions.db' };
     };
if ($@) {tie %session, 'Apache::Session::SQLite', undef, 
     { DataSource => 'dbi:SQLite:/var/www/localhost/perl/storage/sessions.db' };
     }
            #get the session id for later use
            my $session_id = $session{_session_id}; 
            $session{is_logged_in}=1;

        my $sth=$dbh->prepare("update users set last_session_id = ? where (id=?)");
        $sth->execute($session_id, $user_id); 
        return ($user_data,\%session);
    }
    else {return 0}
}
}

sub make_password { 
    my ($user_id,$pass_given,$dbh) = @_;
    my ($s,$p,@t);
    # make random salt
    @t=('a'..'z',0..9);
    $s .= $t[(rand $#t)] for (0..5);
    $p=sha256_hex($pass_given, "{$s}");
    my $sth=$dbh->prepare("update users set password = ? where (id=?)");
    return $sth->execute("${s}:${p}", $user_id); 
}
