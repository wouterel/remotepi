#!/usr/bin/perl
# C) 2013 SZABO Gergely <szg@subogero.com> GNU AGPL v3
use URI::Escape;
use CGI::Carp qw(fatalsToBrowser);
sub ls;

# Common head part for normal page and AJAX responses
print <<HEAD;
Content-type: text/html

<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
HEAD

# Handle AJAX requests
$get_req = uri_unescape $ENV{QUERY_STRING};
if ($get_req eq 'S') {
    print "</head><body>";
    system "omxd", $get_req;
    print "</body></html>";
    exit 0;
} elsif ($get_req =~ /^[NRr.pfFn]$/) {
    print "</head><body></body></html>";
    `omxd $get_req` if $get_req;
    exit 0;
} elsif ($get_req =~ /^home/) {
    (my $dir = $get_req) =~ s/^home //;
    print "</head>";
    ls $dir;
    print "</html>";
    exit 0;
} elsif ($get_req) {
    print "<!-- $get_req -->\n";
    exit 0;
}

# Or continue the normal page
print <<HEAD2;
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<script src="status.js"></script>
<script src="raspberry.js"></script>
<script src="controls.js"></script>
<link rel="stylesheet" type="text/css" href="style.css">
</head>
HEAD2
if (open BODY, "body.html") {
    print while <BODY>;
    close BODY;
}
print "</html>\n";

# Browse Raspberry Pi
sub ls {
    my $dir = shift;
    my $root;
    if (open CFG, "/etc/remotepi.cfg") {
        $root = <CFG>;
        chomp $root;
        close CFG;
    } else {
        $root = "/home";
    }
    # Return to root dir upon dangerous attempts
    $dir = $dir =~ /^\./ ? $root : "$root$dir";
    # Sanitize dir: remove double slashes, cd .. until really dir
    $dir =~ s|(.+)/.+|$1| while ! -d $dir;
    print "<body>\n";
    opendir DIR, $dir;
    push @files, $_ while readdir DIR;
    closedir DIR;
    foreach (sort @files) {
        next if /^\.$/;
        next if /^\.\w/;
        next if /^\.\.$/ && $dir eq "$root/";
        if (-d "$dir/$_") {
            print <<DIR;
<p><a href="javascript:void(0)" onclick="rpi.cd(&quot;$_&quot;);">$_/</a></p>
DIR
        } else {
            print <<FILE;
<p>$_</p>
FILE
        }
    }
    print "</body>\n";
}
