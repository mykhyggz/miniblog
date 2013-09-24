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


my $r = shift;
my $cgi = CGI->new( $r );
my $args = $cgi->Vars;
our $debug = 1;
our $limit = 3;
our $default_actions = {Admin=>['Logout','Articles'], User=>['Logout'], 'Guest'=>['Login'] };
our $default_functions = {Admin=>['Add', 'Edit'], User=>['Comment'] };

our $announce_yaml = "announce.yml";

# Actions: Single things like login/out, preview, publish, etc. GET links
# Login Logout
our $actions_header = "Actions";

# Functions: things that may have actions associated, like new, edit, etc. POST 
our $functions_header = "Functions";

our $footer = '';

our $myurl='/cgi-perl/miniblog.pl';
our $storage_path = '/var/www/localhost/perl/storage';
our $yaml_path = '/var/www/localhost/htdocs/blogfiles';
our $session_id = '';

our $header = <<"EOF";
<!DOCTYPE html>
<html><head><title>Apache::MiniBlog The Lightweight, fast Weblog </title>
<link href="/css/miniblog_layout.css" rel="stylesheet" type="text/css"><meta charset="UTF-8">
<style type="text/css">

h1 {
  font: bold 2em Sans-Serif;
  margin: 1em 0 .15em 0;
}
h2 { 
  font: bold 1.5em Sans-Serif;
  margin: 0 0 .15em 0; 
}
p {
  margin: 2em 0 1em 7em;
}

hr {
  color rgb(200,200,200); 
  width: 50%; margin-top: 2em; margin-bottom: 3em;
} 

article h2, article h3, article, h4 {
 font-family: Helvetica,Arial,sans-serif;
 color: rgb(120, 120, 120);
 margin: 0 0 0 0
}

article h1, article h2 { 
 color: rgb(200, 200, 200);
} 

article p {
 color: rgb(50, 50, 50);
 font-family: Bookman,Times,serif; 
 font-size: 10pt;
}
</style>
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

# grab session from the session asked for
        my %session; 
        tie %session, 'Apache::Session::SQLite', $session_id, 
                { DataSource => "dbi:SQLite:$storage_path/sessions.db" }; 


        my $action = $args->{action};


# check for action
# here we can cascade a 'dispatch' to some function
     if ( my $action = $args->{action} ){

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
# in theory, all else should fail?
# we were probably logged in, real action, or breakage 
        if ($session{is_logged_in}){

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

print "Action = ", $action if $debug;

# probably logged in, must want to see *something*
                    if ($action eq 'Default'){ 
                        $footer =
                    make_footer(undef, undef, $session_id, $user_data->{role});

                        my $post =
                        render_post([$session{last_yaml},LoadFile("$yaml_path/$session{last_yaml}")],$session_id, 0);
                        print <<"EOF";
$header
$post
$footer
EOF
                    } # action:Default   
                    elsif ($action eq 'Articles'){
# my ( $actions_links, $functions_forms, $session_id, $role, $link_wanted, $article, $caller) = @_; 
public_reader(undef, undef, $session_id, $user_data->{role}, 1, undef, 'Articles'); # link wanted
                        
                    } # action:Articles

                    elsif ($action eq 'Pick'){ 
                        my $yaml = $args->{file};
# change to public_render here
# we need to reset the offset to *this file* :(
                        if ($user_data->{role} eq 'Admin'){
                            $footer = make_footer
                            (['Logout'], ['Edit'], $session_id, $user_data->{role},$yaml);
                        }
                        else { 
                            $footer = make_footer
                            (['Logout'], ['Comment'], $session_id, $user_data->{role},$yaml);
                        }

                        my $post = render_post
                          ([$yaml,LoadFile("$yaml_path/$yaml")], $session_id,0);

                        print <<"EOF";
$header 
$post
$footer
EOF
                        
                    } # action:Pick
                } # not logout, opened user data
            } # IF LOGGED IN
        } # IF ACTION #if logged in 
        else { # empty action with session

# pagination track?
# so, most folks will wind up here, session, not logged in, no action 

public_reader(undef, undef, $session_id); 
        }

    undef %session;
    } # if session
    elsif (my $action = $args->{action} ){ 

print 'action: ', $action if $debug;

# no session, so requests from the wild, like a login request 
    }
# Display something to the "public": the root of the blog engine, initial page
# initial session id for pagination
     else {public_reader()}
     # display the root of the site
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
    print $error;
}

# Action was posted in form
else {

#ADD
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
#EDIT
    elsif ($action eq 'Edit'){ 
        my $yamlfile = ( $args->{'yamlfile'} or $session{last_yaml});
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
# PUBLISH
    elsif ($action eq 'Publish'){ 
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime; 
        $mon += 1; $year += 1900; 
        my $datetime = "$mon/$mday/$year $hour:$min GMT" ;
        my $title =  $args->{Title};
        my $description = $args->{Description};
        my $author = $args->{Author};
        my $copy = $args->{Copy};
        my $post= {title =>$title, description =>$description,
            author =>$author, copy =>$copy, datetime=>$datetime};
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
<html><head> <meta http-equiv="refresh" content="2; url=${myurl}?session_id=$session_id&amp;action=Default"></head><body>
<p> Saved $yaml_file... redirecting</p>
</body></html>
EOF
    }
     
    else {
        # s/b error
$footer = render_footer([],[], $session_id);
        print <<"EOF";
$header
<p>this is logged in, no valid function called.
<p>$args->{action} is not valid. Sorry!</p>
$footer
EOF
    }
} # else we have an action, the action list
        } # session is_logged_in
        else { 
# WTF, post request, but not logged in? 
            print $error;
        }
    } # has session_id passed via form (as in after login and p/u old session)
    else {
# do login, as there's nothing else do do via POST/form if you aren't logged in
        if ((my $user=$args->{username}) && (my $pass=$args->{password})){

            if (my ($user_data, $session) = check_password ( $user, $pass )){ 

# we passed! Go to Admin/User "landing page" with a session passed back.  
                my $session_id = $session->{_session_id};
                my $role = $user_data->{role};
                if ( $role eq 'Admin'){
print "role: ", $role if $debug; 

                public_reader(['Logout','Articles'],['Add','Edit','Users'], $session_id, $role, 0, $announce_yaml);
                }
                else {

                public_reader(['Logout','Articles'],['Add'], $session_id, $role, 0, $announce_yaml); # can edit announce article

                }
 
# my $announce= LoadFile("$yaml_path/$announce_yaml");
# $session->{last_yaml}=$announce_yaml;
# print <<"EOF";
# $header
# <p>Howdy, $user_data->{username}!</p>
# <h2>$announce->{title}</h2>
# <h3>$announce->{description}</h3>
# <h4>$announce->{author}</h4>
# $announce->{copy}
# $footer
# EOF
                
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
    if ($user_name && $pass_given){
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

# get the new list of files 
        opendir  D, $yaml_path or die $!; 
            my @yaml_files =  grep (! /^\.{1,2}$/, sort (readdir D));
# pull out our announcement to the users 
            @yaml_files = map {grep (! /^$announce_yaml$/, $_)} @yaml_files;
            
# put stuff in the user record
                $session{dirlist} = [@yaml_files];
                $session{offset} = 0; # reusing old session, is that an issue?
                $session{last_yaml} = $announce_yaml; # shouldn't be needed..??
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
    my ( $actions_links, $functions_forms, $session_id, $role, $yamlfile) = @_;
    $role = 'Guest' unless $role;
    $yamlfile = '' unless $yamlfile;
    $session_id = '' unless $session_id;

# pass just a role to get defaults... worth it? A Guest role set is needed.
    $actions_links = $default_actions->{$role} unless $actions_links;
    $functions_forms = $default_functions->{$role} unless $functions_forms;
# a list of usable "actions_links"
    my $actions = '';
    $actions .= "<li><a href=\"${myurl}?session_id=${session_id}&amp;action=$_\">$_</a></li>\n" for @$actions_links;

# a list of usable "functions_forms"
my $functions = ''; 

$functions .= "<form action=\"$myurl\" method=\"post\">
<input type=\"hidden\" name=\"session_id\" value=\"$session_id\">
<input type=\"hidden\" name=\"action\" value=\"$_\">
<input type=\"hidden\" name=\"yamlfile\" value=\"$yamlfile\"> 
<input type=\"submit\" value=\"$_\"></form>" for @$functions_forms;

$footer = <<"EOF"; 
</section><nav class="main-nav">
    <h3>$actions_header</h3>
    <ul>
$actions
    </ul>
  </nav> 
  <aside class="main-sidebar">
    <h3>$functions_header</h3>
$functions
  </aside></div></body></html>
EOF
return $footer;
}

sub render_post {
    # if a single post is wanted, called once, or in a loop for a page of posts
    my ( $yamlfile, $session_id, $link_wanted) = @_;
    my $yaml = $yamlfile->[0];
    my $post = $yamlfile->[1];
    $session_id = '' unless $session_id; # no undef warnings below
    my $copy = join "</p>\n<p>", (split /\r\n(?:\r\n)+/, $post->{copy});
# don't do this, I think.
#    $copy =~ s/\r\n/<br \/>/g;
    $copy = '<p>' .  $copy  . '</p>';
    my $drill_link ='';
    $drill_link= "<a href=\"${myurl}?action=Pick&amp;file=$yaml&amp;session_id=$session_id\">Link</a>" if ($link_wanted);
    return <<"EOF";
<article>  
<h1>$post->{title}</h1>
<h5>$post->{description}</h5>
<h4>$post->{author}</h4>
<h6>$post->{datetime}</h6>
$copy
$drill_link
<hr /> </article>
EOF
}

sub public_reader {
    
    my ( $actions_links, $functions_forms, $session_id, $role, $link_wanted, $article, $caller) = @_; 

    my %session; 
    tie %session, 'Apache::Session::SQLite', ($session_id || undef),
 { DataSource => "dbi:SQLite:$storage_path/sessions.db" }; 

    $session_id = $session{_session_id};
    $footer = make_footer($actions_links, $functions_forms, $session_id, $role);
    my $entries = '';
    my $more_needed = '' ;

    if ($article){
        print "rendering an article: ", $article if $debug;
        print "last yaml: ", $session{last_yaml} if $debug;
        $session{last_yaml}=$article;
        $entries = render_post([$article,LoadFile("$yaml_path/$article")], $session_id, $link_wanted);

    }

# render the blog entries
    else {
    my @yaml_files ;
# populate the session with dir listing, if not there 
    if (! $session{dirlist}){
        print "announce: ", $announce_yaml if $debug;
        opendir  D, $yaml_path or die $!; 
        @yaml_files =  grep (! /^\.{1,2}$/, sort (readdir D));
 @yaml_files = map {grep (! /^$announce_yaml$/, $_)} @yaml_files;
        $session{dirlist} = [@yaml_files];
    }
    else {
        @yaml_files = @{$session{dirlist}};
    }

    my $offset = ( (defined $session{offset}) ? $session{offset} : 0 ); 

    my $target = $offset + $limit ;
    my $files_count = $#yaml_files + 1;

    $more_needed = "<a href=\"$myurl?session_id=$session_id&amp;action=Articles\">more</a>";
    if ($target > $files_count){
        $target = $files_count;
        $offset = $files_count - $limit;
    $more_needed = "<h6>hey… that’s all folks!</h6>";
    $session{offset}= 0;
    }

#  update the offset in the session

     $session{offset}=$target + 1;
   my @posts = map {[$_,LoadFile("$yaml_path/$_")]} @yaml_files[$offset .. ($target - 1)]; 
# hack to get links
$link_wanted = 1 if ($caller eq 'Articles');
    $entries .= render_post($_, $session_id,$link_wanted) for (@posts);
}


    print <<"EOF";
$header 
$entries 
$more_needed
$footer

EOF

} # public reader




# vim: paste:ai:ts=4:sw=4:sts=4:expandtab:ft=perl
