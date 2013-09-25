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
<link href="/css/miniblog_styles.css" rel="stylesheet" type="text/css"><meta charset="UTF-8">
<style type="text/css"></style>
</head><body><div class="page-wrap"><section class="main-content">
EOF

our $public_error = <<"EOF";
<html><head> <meta http-equiv="refresh" content="2; url=$myurl"></head><body>
<h2>Whoops!</h2> 
<p>Hmm... there should have been something... but here comes the homepage ;-/</p>
</body></html>
EOF

$r->content_type('text/html');

my $method = $r->method(); 

# if a 'GET', dispatch a few basic commands, all edits are POST
if ($method eq 'GET'){

    # if a session id, then we have been here
    if (my $session_id = $args->{session_id}){

# grab session from the session asked for
# not DRY, as we do it again twice, but IDK about stuffing it somewhere.
# as it's crappy to write to a tied hashREF.

        my %session; 
        tie %session, 'Apache::Session::SQLite', $session_id, 
                { DataSource => "dbi:SQLite:$storage_path/sessions.db" }; 

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
<input type="hidden" name="session_id" value="$session_id">
<input type="submit" value="Login"></form>
$footer
EOF
exit;
            } # action:Login  - what else 'action' from non-logged-in user?

# we were probably, and should have been, logged in. An 'else' here?
            if ($session{is_logged_in}){

                if ($action eq 'Logout'){ # short-circuit?
                    $session{is_logged_in}=0; 
                  #  $session{offset}=0; #they get new session, so keep offset
                    print <<"EOF";
<html><head> <meta http-equiv="refresh" content="5; url=$myurl"></head><body>
<h2>Logged Out!</h2><p>Redirecting to Home Page</p></body></html>
EOF
                } # action:Logout
                else {
# not logging out, so get user data 
                    my $dbh = DBI->
                        connect("dbi:SQLite:$storage_path/users.db","","",
{ sqlite_use_immediate_transaction => 1, RaiseError => 1, AutoCommit => 1  });
                    my $sth=$dbh->
                        prepare("select * from users where last_session_id=?");

                    $sth->execute($session_id);
                    my $user_data = $sth->fetchrow_hashref(); 

# view a new publish
                    if ($action eq 'Default'){ 
                        public_reader(undef, undef, $session_id,
                            $user_data->{role},0,$session{last_yaml});
                    } # action : Default   

# view a list, paginated
                    elsif ($action eq 'Articles'){ 
                        # link wanted wired into reader 
                        public_reader(undef, undef, $session_id, 
                            $user_data->{role}, 1, undef, 'Articles'); 
                    } # action:Articles

# pick a single post
                    elsif ($action eq 'Pick'){ 
                        my $yaml = $args->{file};
                        $session{last_yaml}=$yaml; 

# TO DO: move the role logic to the render part, or below
# we need to reset the offset to *this file* :(
                        if ($user_data->{role} eq 'Admin'){ 
                            public_reader(['Logout'], ['Edit','Comment'],
                                $session_id, $user_data->{role},0,$yaml);
                        }
                        else {
                            public_reader(['Logout'], ['Comment'],
                                $session_id, $user_data->{role},0,$yaml);
                        }
                    } # action:Pick
                } # not logout, opened user data
            } # IF LOGGED IN
        } # IF ACTION, but not logged in
        else {

# pagination track
# most folks will wind up here, session, not logged in, no action 
            public_reader(undef, undef, $session_id); 
        } # empty action with session

        undef %session; # likely not needed
    } # if session_id provided
    elsif (my $action = $args->{action} ){ 
# should save the request and forward to login 
        print $public_error;
    }
# Display something to the "public": the root of the blog engine, initial page
# and initial session id for pagination
     else {
         public_reader()
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
# get user data from DBI here... 
            my $action = $args->{action};
            my $dbh = DBI->connect("dbi:SQLite:$storage_path/users.db","","",
{ sqlite_use_immediate_transaction => 1, RaiseError => 1, AutoCommit => 1  });
            my $sth=$dbh->prepare("select * from users where last_session_id=?");

            $sth->execute($session_id);
            my $user_data = $sth->fetchrow_hashref();

            my $role = $user_data->{role};

# cascade of 'POST' actions 
#ADD
            if ($action eq 'Add'){ 
        # my $page_to_edit = 'somefile.yml'; <input type="hidden" name="yamlfile" value="$page_to_edit"> 
        # TO DO: Turn this to load_edit_form for 'Add', 'Edit'
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
# put a date on it, title, etc., from the form
                my $datetime = "$mon/$mday/$year $hour:$min GMT" ;
                my $title =  $args->{Title};
                my $description = $args->{Description};
                my $author = $args->{Author};
                my $copy = $args->{Copy};
                my $post= {title =>$title, description =>$description,
                    author =>$author, copy =>$copy, datetime=>$datetime};
                my $yaml_file ;
                unless ($yaml_file = $args->{yamlfile}){
# uuid for the file name... 
                    my $ug =  new Data::UUID;
                    $yaml_file = $ug->to_string($ug->create()) . '_';

# append something useful to it, like the title
                    ( my $hrid = $args->{Title})=~s/[^a-zA-Z0-9]/_/g ;
                    $yaml_file .= $hrid;
                    $yaml_file .= '.yml';        
                }
                DumpFile("$yaml_path/$yaml_file", $post) or die $!;
        print <<"EOF"; 
<html><head> <meta http-equiv="refresh" content="2; url=${myurl}?session_id=$session_id&amp;action=Default"></head><body>
<p> Saved $yaml_file... redirecting</p>
</body></html>
EOF
            }
     
            else {
                error($session_id, "$action ain't valid");
            }
        } # session is_logged_in

# well, try to log 'em in, mr POST request not logged in...
        else {
            if ((my $user=$args->{username}) && (my $pass=$args->{password})){

                if (my ($user_data, $session) = check_password ( $user, $pass,$session{dirlist} )){ 

# we passed! Go to Admin/User "landing page" with a session passed back.  
                my $session_id = $session->{_session_id};
                my $role = $user_data->{role};
                    if ( $role eq 'Admin'){ 
                        public_reader(['Logout','Articles'],['Add','Edit','Users'], $session_id, $role, 0, $announce_yaml);
                    }
                    else {

                        public_reader(['Logout','Articles'],['Add'], $session_id, $role, 0, $announce_yaml); # can edit announce article

                    }
                undef $session; # likely not needed
                } # password_ok, new session and landing pages
                else {
                   error(undef,"bad login"); 
                }
            } # provided user and pass 
            else {
# WTF, post request, but no session is_logged_in? 
                   error(undef,"login first.. how'd you even *get* here?");
            }
        } # has session_id passed via form but not logged in 
    } # has session ID
} # POST

     ################### SUBS ####################

sub check_password {
    my ($user_name, $pass_given,$dir_list) = @_;
    if ($user_name){
        my $dbh = DBI->connect("dbi:SQLite:$storage_path/users.db","","", { sqlite_use_immediate_transaction => 1, RaiseError => 1, AutoCommit => 1  });
        my $sth = $dbh->prepare("select * from users where username=?");
        $sth->execute($user_name);
        my $user_data = $sth->fetchrow_hashref();

        my $user_id = $user_data->{ id }; # we never use this, do we?

# we get the last session when logging in, in theory, always the same
# when the sessions.db wants to be gone, filter on last session id
# in the users.db

        my $session_id = $user_data->{ last_session_id }; 
        my $hash_returned = $user_data->{password};

        if (! $hash_returned){

# user has no password stored, get one in there
# first Admin login, or temporary password request for new user with password

            if (! $pass_given){ # post a password 
                $footer = make_footer([], []);
                print <<"EOF";
$header
<p>$user_name, you have an empty password. This will not do.</p>
<form action="$myurl" method="post">
Password: <input type="password" name="password"> 
<input type="hidden" name="username" value="$user_id">
<input type="submit" value="Set Password"></form>
$footer
EOF
                exit;
            }
            elsif (make_password( $user_id, $pass_given, $dbh)){
                    print <<"EOF";
<html><head><meta http-equiv="refresh" content="5; url=${myurl}?action=Login"></head><body><p>Congrats! $user_name has a password! Redirecting to login...</p></body></html>
EOF
                    exit; 
                } 
            else {
                print $public_error;
            } 
        } # no hash  in DB 
        else {

# we have a password hash in DB to match, so log 'em in
            my ($salt,$hash_tomatch) = split ':', $hash_returned;
            my $sha_hash = sha256_hex($pass_given, "{$salt}"); 

            if ($sha_hash eq $hash_tomatch){

# DB entry matched against calculated hash, so authenticated
                my %session;
                eval { tie %session, 'Apache::Session::SQLite', $session_id, 
                     { DataSource => "dbi:SQLite:$storage_path/sessions.db" };
                };
                if ($@) { tie %session, 'Apache::Session::SQLite', undef, 
                     { DataSource => "dbi:SQLite:$storage_path/sessions.db" };
                }

                $session{is_logged_in} = 1; 
                my $session_id = $session{_session_id}; 

# get the new list of files 
# TO DO: Pass this from the anonymous session
if (! $dir_list){

print "LOGIN opening dirlist" if $debug;

        opendir  D, $yaml_path or die $!; 
            my @yaml_files =  grep (! /^\.{1,2}$/, sort (readdir D));
# pull out our login announcement
            @yaml_files = map {grep (! /^$announce_yaml$/, $_)} @yaml_files; 
                $session{dirlist} = [@yaml_files];
}
else {
$session{dirlist} = $dir_list;
}
                my $sth=$dbh->prepare
                    ("update users set last_session_id = ? where (id = ?)");
                $sth->execute($session_id, $user_id); 
# return a reference to this session and the user data hashes
                return ($user_data,\%session);
            } # password matched
            else { 
                return 0
            } # password failed
        } # has passhash to match in DB 
    } # we got a user name
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
        print "PUBLIC READER populating session with dirlist" if $debug;
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
    $caller =  "&amp;action=$caller" if $caller; # leave action undef
    $more_needed = "<a href=\"$myurl?session_id=${session_id}${caller}\">more</a>";
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


sub error {
my ($session_id, $errorstring) = @_;
    $footer = make_footer([],[], $session_id);
    my $spacer = '&nbsp;' x 100;
    print <<"EOF";
$header
<p>$spacer</p>
<p>$errorstring</p>
$footer
EOF
}

# vim: paste:ai:ts=4:sw=4:sts=4:expandtab:ft=perl
