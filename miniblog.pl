package Apache::MiniBlog;
use strict;
use warnings;
no warnings 'redefine';

use DBI;
use CGI qw/:cgi/;
use Apache::Session::SQLite; 
# use Apache2::Const qw(:common);
use Digest::SHA qw/sha256_hex/;

# use 5.12.0;

my $r = shift;
my $cgi = CGI->new( $r );
my $args = $cgi->Vars;

our $myurl='http://localhost/cgi-perl/miniblog.pl';
our $storage_path = '/var/www/localhost/perl/storage';

$r->content_type('text/html');
our $header = "<html><head><title>Apache::MiniBlog The Lightweight, fast Weblog </title></head><body>";

our $error = <<"EOF";
<html><head> <meta http-equiv="refresh" content="5; url=$myurl"></head><body>
<h2>Whoops!</h2> 
<p>Hmm... there should have been something... but here comes the homepage ;-/</p>
</body></html>
EOF

my $method = $r->method(); 

# if a 'GET', dispatch a few basic commands, all edits are POST
if ($method eq 'GET'){
    if (my $session_id = $args->{session_id}){ 

# we were logged in, real action, or breakage 
        if ( my $action = $args->{action} ){
# check for action
            my %session; 
            tie %session, 'Apache::Session::SQLite', $session_id, 
                    { DataSource => "dbi:SQLite:$storage_path/sessions.db" }; 

# here we can cascade a 'dispatch' to some function
            if ($action eq 'Logout'){
                $session{is_logged_in}=0; 
                undef %session; 
                print <<"EOF";
<html><head> <meta http-equiv="refresh" content="5; url=$myurl"></head><body>
<h2>Logged Out!</h2> 
<p>Session: $session_id<br>Action: $action</p>
</body></html>
EOF
            } # action:Logout
            undef %session; # less likely SQLite locks?
        } # if session and action
        else { # empty action with session
        }
    } # if session
    elsif (my $action = $args->{action} ){ 

# no session, so requests from the wild, like a login request 
        if ($action eq 'Login') {
        print <<"EOF";
$header
<h3>Login Here</h3> 
<form action="$myurl" method="post">
Username: <input type="text" name="username">
Password: <input type="password" name="password"> 
<input type="submit" value="Login">
</form></body></html> 
EOF
        } # action:Login
        # if action = request login with comment privs and a comment
        # if action = contact, ...?
    }
    else {
# Display something to the "public": the root of the blog engine
        print <<"EOF";
$header
<p> This will be something, soon.  </p>
<a href="${myurl}?action=Login">Login</a>
<ul>
<li>this</li>
<li>that</li>
</ul>
</body></html> 
EOF
    } # display the root of the site
} # GET

elsif ($method eq 'POST') {

# here we have the login, and editing and writing functions 
    if (my $session_id=$args->{session_id}){

# get our old session, which s/b there b/c you just logged in... or forgot
# to log out and you (or someone else) logged in with session id only...??
        my %session; 
        tie %session, 'Apache::Session::SQLite', $session_id,
     { DataSource => "dbi:SQLite:$storage_path/sessions.db" }; 

# the extent of our security, so don't forget to log *out*! ;-)
        if ($session{is_logged_in}){ 

# the meat of it, "is logged in", now, what can user/admin do?
# get user data from DBI here... 

            my $dbh = DBI->connect("dbi:SQLite:$storage_path/users.db","","",
{ sqlite_use_immediate_transaction => 1, RaiseError => 1, AutoCommit => 1  });
            my $sth=$dbh->prepare("select * from users where last_session_id=?");

            $sth->execute($session_id);
            my $user_data = $sth->fetchrow_hashref(); 
            $session_id = $session{_session_id};
            my $ua = $r->headers_in->{'User-Agent'}; 
            print <<"EOF";
$header
<h4>remember to log out!</h4>
<a href="${myurl}?session_id=${session_id}&action=Logout">logout</a>
<p>this should be config options, if no config, I guess,
or a full admin page</p>
<form action="$myurl" method="post"> 
<input type="hidden" name="session_id" value="$session_id">
<input type="hidden" name="action" value="publish">
<input type="submit" value="Publish">
</form></body></html> 
EOF

        } # is_logged_in
        else{ 
            print $error;
            # WTF, session open, post request, but not logged in? 
        }
    } # has session_id
    else { 
# do login, no session yet
        if ((my $user=$args->{username}) && (my $pass=$args->{password})){
            if (my ($user_data, $session) = check_password ( $user, $pass )){ 
# we passed! Admin/User "landing page" and a new session, passed back!
                my $session_id = $session->{_session_id};
                if ($user_data->{id} == 0){
# admin page, add users / approve comments
                print <<EOF;
$header
<p>Howdy, $user_data->{username}!</p> 
<p>Here is where we can go to different places, the landing page</p> 
<p>Reminder: Do we need Apache::DBI?</p> 
<p>Add users?</p>
<form action="$myurl" method="post"> 
<input type="hidden" name="session_id" value="$session_id">
<input type="hidden" name="action" value="AddUsers">
<input type="submit" value="Add Users">
</form></body></html> 
EOF
                }
            else {
# user page, 'edit comments'...??
# user page, 'request cotrib status'...??
                print <<EOF;
$header
<p>Howdy, $user_data->{username}!</p> 
<p>Here is where we can go to different places, the landing page</p> 
<form action="$myurl" method="post"> 
<input type="hidden" name="session_id" value="$session_id">
<input type="hidden" name="action" value="">
<input type="submit" value="go to site">
</form></body></html> 
EOF
                }
            } # password_ok, landing pages
            else {
            print $error;
            }
        } # provided user and pass
    } # no session ID
} # POST

sub check_password {
    my ($user_name, $pass_given) = @_; 
    if ($user_name){
        my $dbh = DBI->connect("dbi:SQLite:$storage_path/users.db","","", { sqlite_use_immediate_transaction => 1, RaiseError => 1, AutoCommit => 1  });
        my $sth = $dbh->prepare("select * from users where username=?");
        $sth->execute($user_name);
        my $user_data = $sth->fetchrow_hashref();
        my $hash_returned = $user_data->{password};
        my $user_id = $user_data->{id};
        my $session_id = ( $user_data->{last_session_id} || undef );

        if (! $hash_returned){ 

# user has no password stored, get one in there 
            if ($pass_given){

    # first Admin login, or temporary password request for new user with password
                if  (make_password( $user_id, $pass_given, $dbh)){
                    print <<"EOF";
<html><head><meta http-equiv="refresh" content="5; url=$myurl"></head><body>
<p>Congrats! $user_name has a password! Redirecting to login...</p>
<p>ID: $user_data->{id}</p>
<p>PWD: $user_data->{password}</p>
</body></html>
EOF
                } # password made, redirected
                else {
                    print $error;
                    # error, password routine
                }
            }
# user still needs to provide a password, prompt for one
            else { 
                print <<"EOF";
$header
<p>$user_name, you have an empty password. This will not do.</p>
<form action="$myurl" method="post">
Password: <input type="password" name="password" method="post"> 
<input type="hidden" name="username" value="$user_id">
<input type="submit" value="Set Password">
</form></body></html> 
EOF
            } # pass not given, or pass given and hash stored
        } # user name, but no hash 
# we have a password hash in DB to match, so log 'em in
        else {
            my ($salt,$hash_tomatch) = split ':', $hash_returned;
            my $sha_hash = sha256_hex($pass_given, "{$salt}"); 

# match DB entry against calculated hash
            if ($sha_hash eq $hash_tomatch){
                my %session; 
# make a fresh session for a first-time visitor, or maybe re-open
# "maybe" b/c the sessions DB should be 
                eval { tie %session, 'Apache::Session::SQLite', $session_id, 
                     { DataSource => "dbi:SQLite:$storage_path/sessions.db" };
                };
                if ($@) { tie %session, 'Apache::Session::SQLite', undef, 
                     { DataSource => "dbi:SQLite:$storage_path/sessions.db" };
                }
# mark the session logged in
                $session{is_logged_in} = 1;
# get the session id
                my $session_id = $session{_session_id}; 
# put in the user record
                my $sth=$dbh->prepare("update users set last_session_id = ? where (id=?)");
                $sth->execute($session_id, $user_id); 
# return a reference to this session
                return ($user_data,\%session);
            } # password matched
            else {
                return 0
            } # password failed
        } # has passhash to match in DB
    } # we got a user name
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

# vim: paste:ai:ts=4:sw=4:sts=4:expandtab:ft=perl
