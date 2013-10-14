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
use Text::Markdown 'markdown';
use HTML::Entities;

my $r = shift;
my $cgi = CGI->new( $r );
local our $args = $cgi->Vars;

our $debug = 1;

our $default_actions = {Admin=>['Logout','Articles'], User=>['Logout'], 'Guest'=>['Login'] };
our $default_functions = {Admin=>['Add'], User=>[] };


# this may not be reliable at all under handler routine or certain m_p setups.
my $location = $ENV{'SCRIPT_FILENAME'};
(my $path = $location) =~s#^(.+)/[^/]+#$1#;

our $myurl= $ENV{'SCRIPT_NAME'};

# open site config
# this should have a create routine if it doesn't exist
our $config = LoadFile("$path/siteconfig.yml") or die $path, " ", $!; 

our $limit = $config->{post_limit};
our $title = $config->{blog_name};
our $announce_yaml = $config->{admin_page}; 
our $actions_header = $config->{action_hdr};
our $functions_header = $config->{functn_hdr}; 

our $storage_path = $config->{db_path};
our $yaml_path = $config->{yaml_path};

# TO DO: remove hardcoded css href
our $header = <<"EOF";
<!DOCTYPE html>
<html><head><title>$title</title>
<link href="/css/miniblog_layout.css" rel="stylesheet" type="text/css"><meta charset="UTF-8">
<link href="/css/miniblog_styles.css" rel="stylesheet" type="text/css"><meta charset="UTF-8">
<style type="text/css"></style>
</head><body><div class="page-wrap"><section class="main-content">
EOF

our $public_error = <<"EOF";
<html><head> <meta http-equiv="refresh" content="5; url=$myurl"></head><body>
<h2>Whoops!</h2> 
<p>Hmm... there should have been something... but here comes the homepage ;-/</p>
</body></html>
EOF

our $footer = '';

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
            } # action:Login

            elsif ($action eq 'Tags') {
                # TO DO: query for posts matching tags
                # s/b in the session data
                # and PUT THE TAGCLOUD in footer
                $footer = make_footer([], [], undef);
                print <<"EOF";
$header
<h3>you asked for tags</h3> 
<form action="$myurl" method="post">
Username: <input type="text" name="username">
Password: <input type="password" name="password"> 
<input type="hidden" name="session_id" value="$session_id">
<input type="submit" value="Login"></form>
$footer
EOF
exit;
            } # action:Tags
# we were probably, and should have been, logged in. An 'else' here?
            if ($session{is_logged_in}){

                if ($action eq 'Logout'){ # short-circuit?
                    $session{is_logged_in}=0; 

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
                            $user_data->{role},$session{last_yaml});
                    } # action : Default   

# view a list, paginated
                    elsif ($action eq 'Articles'){ 
                        # link wanted wired into reader 
                        public_reader(undef, undef, $session_id, 
                            $user_data->{role}, undef, 'Articles'); 
                    } # action:Articles

# pick a single post
                    elsif ($action eq 'Pick'){ 
                        my $yaml = $args->{file};
                        $session{last_yaml}=$yaml; 

# TO DO: move the role logic to the render part, or below 
                        if ($user_data->{role} eq 'Admin'){ 
                            public_reader(['Logout'], ['Edit','Comment'],
                                $session_id, $user_data->{role},$yaml);
                        }
                        elsif($user_data->{role} eq 'User') {
                            public_reader(['Logout'], ['Comment'],
                                $session_id, $user_data->{role},$yaml);
                        }
                        else {
                            public_reader([], [],
                                $session_id, $user_data->{role},$yaml);
                        }
                    } # action:Pick
                } # not logout, opened user data
            } # IF LOGGED IN
        } # IF ACTION, but not logged in
        else {

# pagination track
# most folks will wind up here, session, not logged in, no action 
            public_reader(undef, undef, $session_id, 'Guest'); 
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
#( $actions_links, $functions_forms, $session_id, $role, $article, $caller)
         if ($args->{file}){ 
             public_reader(undef,undef,undef,'Guest',$args->{file})
         }
         else {
             public_reader(undef,undef,undef,'Guest')
         }
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
   
                $footer = make_footer(['Logout'],[],$session_id,$role); 
                my $form = load_edit_form($session_id,$user_data->{username});
                print <<"EOF";
$header
$form
$footer
EOF
            }
#EDIT
            elsif ($action eq 'Edit'){ 
    
                my $yamlfile = ( $args->{'yamlfile'} );#or $session{last_yaml});
                my $post = LoadFile("$yaml_path/$yamlfile");

                my $form = load_edit_form($session_id,$user_data->{username},$post,$yamlfile);

                $footer = make_footer(['Logout'],[],$session_id,$role,$yamlfile);

                print <<"EOF";
$header
$form
$footer
EOF
            }
# PUBLISH
            elsif ($action eq 'Publish'){
                my $datetime = time;
                my $title =  enc($args->{Title});
                my $description = enc($args->{Description});
                my $author = enc($args->{Author});
                my $copy = enc($args->{Copy});
                my $tags = enc($args->{Tags});
                my $post= {title =>$title, description =>$description,
                    author =>$author, copy =>$copy, datetime=>$datetime,
                    tags => $tags,};
                my $yaml_file ;
# re-use file name or make a new one
                # TO DO: Make sure the file exists if *re*-using the name
                unless ($yaml_file = $args->{yamlfile}){
# uuid for the file name... 
                    my $ug =  new Data::UUID;
                    $yaml_file = $ug->to_string($ug->create()) . '_';
# TO DO: append directory list, rather, we need to re-load 
# append something useful to it, like the title
                    ( my $hrid = $args->{Title})=~s/[^a-zA-Z0-9]/_/g ;
                    $yaml_file .= $hrid;
                    $yaml_file .= '.yml';        
                }
# passed to Default view
        $session{last_yaml}=$yaml_file; 

                DumpFile("$yaml_path/$yaml_file", $post) or die $!;
# re-read the directory list, last edit is now first
        $session{dirlist} = get_posts();
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

                if (my ($user_data, $session) =
                    check_password ( $user, $pass,$session{dirlist} )){ 

# we passed! Go to Admin/User "landing page" with a session passed back.  
                my $session_id = $session->{_session_id};
                my $role = $user_data->{role};

# ( $actions_links, $functions_forms, $session_id, $role, $article, $caller)
                    if ( $role eq 'Admin'){
                        public_reader(['Logout','Articles'],['Add','Edit','Users'], $session_id, $role, $announce_yaml);
                    }
                    else {
                        public_reader(['Logout','Articles'],['Add'], $session_id, $role, $announce_yaml); # can edit announce article

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
    # we get the dir_list from initial view, so s/b up-to-date
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
# TO DO: predictible session id c/b bad. Reset to new one

        my $session_id = $user_data->{ last_session_id }; 
        my $hash_returned = $user_data->{password};

        if (! $hash_returned){

# user has no password stored, get one in there
# first Admin login, or temporary password request for new user with password

            if (! $pass_given){ 
                # TO DO: rip this out, or use it
                $footer = make_footer([], []);
                print <<"EOF";
$header
<p>$user_name, you have an empty password. This will not do.</p>
<form action="$myurl" method="post">
Password: <input type="password" name="password"> 
Again, then Password: <input type="password" name="password-match"> 
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
                # TO DO: fix the hardcoded sessions db
                my %session;
                eval { tie %session, 'Apache::Session::SQLite', $session_id, 
                     { DataSource => "dbi:SQLite:$storage_path/sessions.db" };
                };
                if ($@) { tie %session, 'Apache::Session::SQLite', undef, 
                     { DataSource => "dbi:SQLite:$storage_path/sessions.db" };
                }

                $session{is_logged_in} = 1; 
                $session{last_yaml}=$announce_yaml;
                my $session_id = $session{_session_id}; 

                if (! $dir_list){ 
                    error($session_id,
                        "i guess we need to list the dirs here after all?");
                }
                else {
                    # we populate with new dirlisting here on login
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
    my ( $yamlfile, $session_id, $role ) = @_;
    my $yaml = $yamlfile->[0];
    my $post = $yamlfile->[1];
    $session_id = '' unless $session_id; # no undef warnings below
    # my $copy = join "</p>\n<p>", (split /\r\n(?:\r\n)+/, $post->{copy}); 
    # $copy = '<p>' .  $copy  . '</p>';
    my $copy = markdown($post->{copy});
    my $action = '';
    $action="&amp;session_id=$session_id&amp;action=Pick" if
        (($role eq 'Admin') || ($role eq 'User'));
    my $drill_link= "<a href=\"${myurl}?file=${yaml}$action\">Link</a>" ;
my $taglinks;
for my $tag (split /\s+/, $post->{tags}){
$taglinks .= "<em>$tag</em>&nbsp;";
}
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime ($post->{datetime} ); 
                $mon += 1; $year += 1900; 
# put a date on it, title, etc., from the form
                my $datetime = "$mon/$mday/$year $hour:$min GMT" ;
    return <<"EOF";
<article>  
<h1>$post->{title}</h1>
<h5>$post->{description}</h5>
<h4>$post->{author}</h4>
<h6>$datetime</h6>
$copy
$drill_link
<h6>Tags: $taglinks</h6>
<hr /> </article>
EOF
}


# PUBLIC READER
sub public_reader {
    # should already have a session. Hmmm. 
    # I THINK we can eliminate this call to the session here entirely
    # TO DO: ^^^^^^^^^^^^^^^
    my ( $actions_links, $functions_forms, $session_id, $role, $article, $caller) = @_; 

# sanitize article for ../../ crap. Should probably disallow some other stuff?
    $article =~ s#^[\./]+##g;
    my %session; 
    tie %session, 'Apache::Session::SQLite', ($session_id || undef),
 { DataSource => "dbi:SQLite:$storage_path/sessions.db" }; 

    $caller = '' unless $caller;
    $role = '' unless $role;
    $session_id = $session{_session_id};
    $footer = make_footer($actions_links, $functions_forms, $session_id, $role,$article);
    my $entries = '';
    my $more_needed = '' ;
# print "offset: ", $session{offset} if $debug;
    if ($article){ 
        $session{last_yaml}=$article;
# so this gets set when an article is read
# this would mean nothing, really
#        $session{offset} = map{ grep /^$article$/, $_->[0]} @{$session{dirlist}};

        $entries = render_post([$article,LoadFile("$yaml_path/$article")], $session_id,$role);
 
    }

# render the blog entries
    else {
        my @yaml_files ;

# populate the session with dir listing, if not there 
        if (! $session{dirlist}){
            my $yamlfiles = get_posts(); 
            $session{dirlist} = $yamlfiles;
            @yaml_files = @{$yamlfiles};
        }
        else {
            @yaml_files = @{$session{dirlist}};
        }

# grab the offset from the nav click or the session, or make it up 
    my $offset = ( $args->{offset} || 0 );

    my $target = $offset + ( $limit - 1 ) ;
    my $files_index = $#yaml_files;

    $caller =  "&amp;action=$caller" if $caller; 

# fix if the target would be outside the index
    if ($target >= $files_index){
        $target = $files_index; 
        $more_needed = "<h6>hey… that’s all folks!</h6>";
    }
    else {

    # update the next offset in sequence 
        my $off = $target + 1;
        $more_needed = "<a href=\"$myurl?session_id=${session_id}${caller}&amp;offset=$off\">more</a>";
    }

# parse a few posts
    my @posts = map {[$_->[0],LoadFile("$yaml_path/$_->[0]")]} @yaml_files[$offset .. $target]; 

# "offset" makes the nav back button/key work, fwiw

    $entries .= render_post($_, $session_id,$role) for (@posts);
}


    print <<"EOF";
$header 
$entries 
$more_needed
$footer
EOF

} # public reader


sub enc {
return encode_entities($_[0]); 
}

sub dec {
return decode_entities($_[0]); 
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

sub load_edit_form {
# TO DO: Tags
my ($session_id,$username,$yamldata,$yamlfile)=@_;
my ($title,$description,$author,$copy,$tags) = '';
# all crap from wild has been enc'd, so must be dec'd 
if ($yamldata){
# editing an existing file
$title = dec($yamldata->{title});
$description = dec($yamldata->{description});
$author = dec($yamldata->{author});
$copy = dec($yamldata->{copy});
$tags = dec($yamldata->{tags});
}
else {
# we're making an empty form for new post
$author = $username;
}
return <<"EOF";
<form action="$myurl" method="post">
Title: <input type="text" name="Title" value="$title"><br />
Description: <input type="text" name="Description" value="$description"><br /> 
Author: <input type="text" name="Author" value="$author"><br /> 
Tags: <input type="text" name="Tags" value="$tags"><br /> 
<textarea rows="20" cols="50" name="Copy">$copy</textarea>
<input type="hidden" name="yamlfile" value="$yamlfile">
<input type="hidden" name="action" value="Publish">
<input type="hidden" name="session_id" value="$session_id">
<input type="submit" value="Publish"></form>
EOF

}

sub get_posts {

            opendir  D, $yaml_path or die $!; 
            my @yaml_files =  grep (/^.*\.yml$/, readdir D);
            @yaml_files = sort {$b->[1] cmp $a->[1]}
                map{ [$_, LoadFile("$yaml_path/$_")->{datetime} ]}
                grep (! /^$announce_yaml$/, @yaml_files);
return [@yaml_files];
}
# vim: paste:ai:ts=4:sw=4:sts=4:expandtab:ft=perl
