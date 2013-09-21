package Apache::MiniBlog;
use strict;
use warnings;
no warnings 'redefine';

use DBI;
use CGI qw/:cgi/;
use Apache::Session::SQLite; 
use Digest::SHA qw/sha256_hex/;
use YAML qw/LoadFile DumpFile Load Dump/;
use Data::UUID;

my $debug = 1;
my $r = shift;
my $cgi = CGI->new( $r );
my $args = $cgi->Vars;

our $default_actions = {Admin=>['Logout'], User=>['Logout'] };
our $default_functions = {Admin=>['Add', 'Edit'], User=>['Comment'] };

our $announce_yaml = "announce.yml";

# Actions: Single things like login/out, preview, publish, etc. GET links
# Login Logout
our $actions_header = "Actions";

# Functions: things that may have actions associated, like new, edit, etc. POST 
our $functions_header = "Functions";

# so this changes per rendering
our $footer = undef;

our $myurl='http://localhost/cgi-perl/miniblog.pl';
our $storage_path = '/var/www/localhost/perl/storage';
our $yaml_path = '/var/www/localhost/htdocs/blogfiles';
our $session_id = '';

our $header = <<"EOF";
<html><head><title>Apache::MiniBlog The Lightweight, fast Weblog </title>
<link href="http://localhost/css/miniblog_layout.css" rel="stylesheet" type="text/css" />
</head><body><div class="page-wrap"><section class="main-content">
EOF

our $error = <<"EOF";
<html><head> <meta http-equiv="refresh" content="2; url=$myurl"></head><body>
<h2>Whoops!</h2> 
<p>Hmm... there should have been something... but here comes the homepage ;-/</p>
</body></html>
EOF
$r->content_type('text/html');

my $method = $r->method(); 

# if a 'GET', dispatch a few basic commands, all edits are POST
if ($method eq 'GET'){
    if (my $session_id = $args->{session_id}){ 

# we were probably logged in, real action, or breakage 
        if ( my $action = $args->{action} ){
# print "Aacti: $action $session_id" if $debug;
# grab session from the session asked for
            my %session; 
            tie %session, 'Apache::Session::SQLite', $session_id, 
                    { DataSource => "dbi:SQLite:$storage_path/sessions.db" }; 

            if ($session{is_logged_in}){

# check for action
# here we can cascade a 'dispatch' to some function
                if ($action eq 'Logout'){
                    $session{is_logged_in}=0; 
                    print <<"EOF";
<html><head> <meta http-equiv="refresh" content="5; url=$myurl"></head><body>
<h2>Logged Out!</h2> 
<!--p>Session: $session_id<br>Action: $action</p-->
<p>Redirecting to Home Page</p>
</body></html>
EOF
            
                } # action:Logout
                else {

# get user data 
                    my $dbh = DBI->
                        connect("dbi:SQLite:$storage_path/users.db","","",
{ sqlite_use_immediate_transaction => 1, RaiseError => 1, AutoCommit => 1  });
                    my $sth=$dbh->
                        prepare("select * from users where last_session_id=?");

                    $sth->execute($session_id);
                    my $user_data = $sth->fetchrow_hashref(); 

# probably logged in, must want to see *something*
                    if ($action eq 'Default'){ 
                        $footer =
                    make_footer(undef, undef, $session_id, $user_data->{role});

                        my $post =
                        render_post(LoadFile("$yaml_path/$session{last_yaml}"));
                        print <<"EOF";
$header
$post
$footer
EOF

                    } # action:Default
                } # not logout, opened user data
            } # session is_logged_in

# drop mod_perl session object -- less likely SQLite locks?
            undef %session;
        } # if session and action
        else { # empty action with session
            print $error;
        }
    } # if session
    elsif (my $action = $args->{action} ){ 

# no session, so requests from the wild, like a login request 
        if ($action eq 'Login') {
        $footer = make_footer([], [], undef);
        print <<"EOF";
$header
<h3>Login Here</h3> 
<form action="$myurl" method="post">
Username: <input type="text" name="username">
Password: <input type="password" name="password"> 
<input type="submit" value="Login"></form>
$footer
EOF
        } # action:Login
        # if action = request login with comment privs and a comment
        # if action = contact, ...?
    }

# Display something to the "public": the root of the blog engine
    else {
        $footer = make_footer(['Login'], []);
        opendir  D, $yaml_path or die $!;
        my @yaml_files = map {LoadFile("$yaml_path/$_")} grep(! /^\.{1,2}$/, (readdir D));

        my $entries = '';
        $entries .= render_post($_) for (@yaml_files);
        
        print <<"EOF";
$header 
$entries 
$footer
EOF
    } # display the root of the site
} # GET

elsif ($method eq 'POST') {

# Log-in request starts here, and editing and writing functions 
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
            my $action = $args->{action};
            my $dbh = DBI->connect("dbi:SQLite:$storage_path/users.db","","",
{ sqlite_use_immediate_transaction => 1, RaiseError => 1, AutoCommit => 1  });
            my $sth=$dbh->prepare("select * from users where last_session_id=?");

            $sth->execute($session_id);
            my $user_data = $sth->fetchrow_hashref(); 
            if ($user_data->{role} eq 'Admin'){
                $footer = make_footer( ['Logout'],
                ['Add','Edit', 'AddUser'], $session_id );
            }
            elsif ($user_data->{role} eq 'User'){
                $footer = make_footer(['Logout'], ['Comment'], $session_id);
            }


# no action was given. A "default" page.
if (! $action){
            print <<"EOF";
$header
<h4>remember to log out!</h4>
<p>seems this is the default landing page, if no valid function is called. Cool.

<p>Maybe the recent articles in the middle, actions on the right, where stats would be for a viewer, with navigation (drafts, vs published, etc. ) and meta-actions on the left.</p>
$footer
EOF
}

# Action was posted in form
else {

    if ($action eq 'Add'){ 
        # my $page_to_edit = 'somefile.yml'; <input type="hidden" name="yamlfile" value="$page_to_edit"> 
        print <<"EOF";
$header
<form action="$myurl" method="post">
Title: <input type="text" name="Title" value=""><br />
Description: <input type="text" name="Description" value=""><br /> 
Author: <input type="text" name="Author" value="$user_data->{username}"><br /> 
<textarea rows="20" cols="50" name="Copy">TypeYrShitHere</textarea>

<input type="hidden" name="action" value="Publish">
<input type="hidden" name="session_id" value="$session_id">
<input type="submit" value="Publish"></form>
$footer
EOF
    }
    elsif ($action eq 'Edit'){ 
        my $yamlfile = $session{last_yaml};
        my $post = LoadFile("$yaml_path/$yamlfile"); 

# $actions_links, $functions_forms, $session_id, $role, $yamlfile
        $footer = make_footer(['Logout'],[],$session_id,undef,$yamlfile);

        print <<"EOF";
$header

<form action="$myurl" method="post"> 
Title: <input type="text" name="Title" size=70 value="$post->{title}"><br />
Description: <textarea name="Description" rows=2 cols=80>$post->{description}</textarea><br />
Author: <input type="text" name="Author" size=60 value="$post->{author}"><br />
<textarea rows="20" cols="80" name="Copy">
 $post->{copy}
</textarea><br />
<input type="hidden" name="yamlfile" value="$yamlfile">
<input type="hidden" name="action" value="Publish">
<input type="hidden" name="session_id" value="$session_id">
<input type="submit" value="Publish"></form>
$footer
EOF
    }
    elsif ($action eq 'Publish'){ 
        my $title =  $args->{Title};
        my $description = $args->{Description};
        my $author = $args->{Author};
        my $copy = $args->{Copy}; 

        my $post= {title =>$title, description =>$description,
            author =>$author, copy =>$copy};
        my $ug =  new Data::UUID;
        my $yaml_file = $ug->to_string($ug->create()) . '_';
        ( my $hrid = $args->{Title})=~s/[^a-zA-Z0-9]/_/g ;
        $yaml_file .= $hrid;
        $yaml_file .= '.yml';        
# special cases for special posts
        $yaml_file = $args->{yamlfile} if (defined  $args->{yamlfile});
        DumpFile("$yaml_path/$yaml_file", $post) or die $!; 
        $session{last_yaml}=$yaml_file;
        print <<"EOF"; 
<html><head> <meta http-equiv="refresh" content="2; url=${myurl}?session_id=$session_id&action=Default"></head><body>
<p> Saved $yaml_file... redirecting</p>
</body></html>
EOF
    }
     
} # else we have an action, the action list
        } # session is_logged_in
        else { 
# WTF, session open, post request, but not logged in? 
            print $error;
        }
    } # has session_id
    else { 
# do login, no session yet 
        if ((my $user=$args->{username}) && (my $pass=$args->{password})){
            if (my ($user_data, $session) = check_password ( $user, $pass )){ 
                my $session_id = $session->{_session_id};
# we passed! Go to Admin/User "landing page" with a session passed back.  
                if ($user_data->{role} eq 'Admin'){
                    $footer =
                    make_footer(['Logout'],['Add','Edit','Users'], $session_id);
                }
                else {
                    $footer = make_footer(['Logout'], ['Add'], $session_id);
                }
 
my $announce= LoadFile("$yaml_path/$announce_yaml");
$session->{last_yaml}=$announce_yaml;
print <<"EOF";
$header
<p>Howdy, $user_data->{username}!</p>
<h2>$announce->{title}</h2>
<h3>$announce->{description}</h3>
<h4>$announce->{author}</h4>
$announce->{copy}
$footer
EOF
                
# close the session we opened at successful login
            undef $session;
            } # password_ok, new session and landing pages
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
        my $user_id = $user_data->{ id };
        my $session_id = $user_data->{ last_session_id }; 
        if (! $hash_returned){
    
# user has no password stored, get one in there 
            if ($pass_given){

    # first Admin login, or temporary password request for new user with password
                if  (make_password( $user_id, $pass_given, $dbh)){
                    print <<"EOF";
<html><head><meta http-equiv="refresh" content="5; url=${myurl}?action=Login"></head><body>
<p>Congrats! $user_name has a password! Redirecting to login...</p>
<p>ID: $user_data->{id}</p>
<p>Name: $user_data->{username}</p>
<p>Email: $user_data->{email}</p>
<p>Role: $user_data->{role}</p>
</body></html>
EOF
exit; 
                } # password made, redirected
                else {
                    print $error;
                    # error, password routine
                }
            }
# user still needs to provide a password, prompt for one
            else { 

                $footer = make_footer(['Home'], []);
                print <<"EOF";
$header
<p>$user_name, you have an empty password. This will not do.</p>
<form action="$myurl" method="post">
Password: <input type="password" name="password" method="post"> 
<input type="hidden" name="username" value="$user_id">
<input type="submit" value="Set Password"></form>
$footer
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
                my $sth=$dbh->prepare("update users set last_session_id = ? where (id = ?)");
                $sth->execute($session_id, $user_id); 
# return a reference to this session and the user data
               
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

sub make_footer {
    my ( $actions_links, $functions_forms, $session_id, $role,
    $yamlfile) = @_;
    $role = 'Guest' unless $role;
    $yamlfile = '' unless $yamlfile;
    $session_id = '' unless $session_id;

# pass just a role to get defaults... worth it? A Guest role set is needed.
    $actions_links = $default_actions->{$role} unless $actions_links;
    $functions_forms = $default_functions->{$role} unless $functions_forms;
# a list of usable "actions_links"
    my $actions = '';
    $actions .= "<li><a href=\"${myurl}?session_id=${session_id}&action=$_\">$_</a></li>\n" for @$actions_links;

# a list of usable "functions_forms"
my $functions = ''; 

$functions .= "<form action=\"$myurl\" method=\"post\">
<input type=\"hidden\" name=\"session_id\" value=\"$session_id\">
<input type=\"hidden\" name=\"action\" value=\"$_\">
<input type=\"hidden\" name=\"yamlfile\" value=\"$yamlfile\"> 
<input type=\"submit\" value=\"$_\"></form>" for @$functions_forms;

$footer = <<"EOF"; 
</section><nav class="main-nav">
    <h2>$actions_header</h2>
    <ul>
$actions
    </ul>
  </nav> 
  <aside class="main-sidebar">
    <h2>$functions_header</h2>
$functions
  </aside></div></body></html>
EOF
return $footer;
}

sub render_post {
my $post = shift;
return <<"EOF";
<h2>$post->{title}</h2>
<h3>$post->{description}</h3>
<h4>$post->{author}</h4>
$post->{copy}
<hr />
EOF
}
# vim: paste:ai:ts=4:sw=4:sts=4:expandtab:ft=perl
