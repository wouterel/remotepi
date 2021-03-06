#!/usr/bin/perl
# (C) 2013 SZABO Gergely <szg@subogero.com> GNU AGPL v3
use feature state;
use URI::Escape;
use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
use CGI::Fast;
use IPC::Open2;
use Fcntl ':mode';
use Cwd;
use JSON::XS;
use WWW::U2B;
sub status; sub thumbnail;
sub ls; sub fm; sub run_rpifm; sub rpifm_my; sub byalphanum; sub yt; sub logger;
my ($root, $ytid, %ythits, $fm_my);

# Cleaun up albumart symlink upon exit
$SIG{TERM} = sub { thumbnail };

# Get root directory
if (open CFG, "/etc/omxd.conf") {
    $root = <CFG>;
    chomp $root;
    $root =~ s|user=|/home/|;
    $root = "/home" unless -d $root;
    close CFG;
} else {
    $root = "/home";
}
# Open log file
open LOG, ">remotepi.log";

# Load radio station data
rpifm_my;

# FastCGI main loop to handle AJAX requests
while (my $cgi = new CGI::Fast) {
    my $method = request_method;
    my $data;
    if ($method eq 'POST'){
        $data = eval { decode_json $cgi->param('POSTDATA') };
        if ($@) {
            print header 'text/html', '400 Malformed JSON Request';
            next;
        }
    }
    my $get_req = uri_unescape $ENV{QUERY_STRING};
    if ($get_req =~ /^S/) {
        status $get_req, $data;
    } elsif ($get_req =~ /^home/) {
        (my $dir = $get_req) =~ s/^home//;
        ls $dir, $data;
    } elsif ($get_req =~ /^fm/) {
        (my $cmd = $get_req) =~ s|^fm/?||;
        fm $cmd, $data;
    } elsif ($get_req =~ /^yt/) {
        (my $cmd = $get_req) =~ s|^yt/?||;
        yt $cmd, $data;
    } elsif ($get_req) {
        print header 'text/html', '400 Bad request';
        print "<!-- $method $data $get_req -->\n";
    }
}

# Print playlist status
sub status {
    my $cmd = shift;
    my $data = shift;
    if ($data && $data->{cmd} =~ /^[NRr.pPfFnxXhjdDg]$/) {
        `omxd $data->{cmd} $data->{file}`;
    }
    unless (open PLAY, "omxd S all |") {
        print header('text/html', '500 Unable to access omxd status');
        return;
    }
    print header(-type => 'application/json', -charset => 'utf-8');
    my $now = <PLAY>;
    chomp $now;
    my ($doing, $at, $of, $what) = split /[\s\/]/, $now, 4;
    # Replace track name with internet radio if needed
    foreach (keys %$fm_my) {
        next unless $fm_my->{$_}{listen} eq $what;
        my $url = $_;
        $what = $fm_my->{$_}{title};
        if ($cmd =~ m|^S\d*/details|) {
            my $st_page = `curl -L "internet-radio.com/search/?radio=$url" 2>/dev/null`;
            $st_page =~ m|<br>[\s\n]*<b>(.+?)</b>|s;
            $what .= "\n$url\n$1";
        }
    }
    # Remove root from track name if local file
    my ($dir) = $what =~ m|^(/.+)/[^/]+$|;
    $what =~ s/$root//;
    # Replace track name with YouTube id if needed
    $what =~ s|.*\.u2bfifo$|/YouTube/$ythits{$ytid}|;
    # Construct JSON response
    my $response = { doing => $doing, at => $at+0, of => $of+0, what => $what };
    my $i = 0;
    @{$response->{list}} = map {
        s/^(> )?$root(.+)\n/$2/;
        { name => $i++, label => $_, ops => [ qw(g x) ] }
    } <PLAY>;
    $response->{image} = thumbnail $dir;
    print encode_json $response;
    close PLAY;
}

# Get thumbnail image link from current playback directory
sub thumbnail {
    my $dir = shift;
    state ($dir_old, $img_old);
    return $img_old if $dir eq $dir_old;
    unlink $img_old;
    $img_old = '';
    $dir_old = $dir;
    return unless $dir && opendir DIR, $dir;
    my $img;
    while (readdir DIR) {
        next unless /(png|jpe?g)$/i;
        next if $_ eq 'rpi.jpg';
        symlink "$dir/$_", $_ or logger "Unable to symlink $_";
        $img_old = $_;
        $img = $_;
        last;
    }
    close DIR;
    return $img;
}

# Browse Raspberry Pi
sub ls {
    my $dir = shift;
    my $data = shift;
    if ($data) {
        print header 'text/plain';
        `omxd $data->{cmd} "$root$data->{file}"` if $data->{cmd} =~ /[iaAIHJ]/;
        return;
    }
    # Return to root dir upon dangerous attempts
    $dir = $dir =~ /^\.|^$/ ? $root : "$root$dir";
    # Sanitize dir: remove double slashes, cd .. until really dir
    $dir =~ s|(.+)/.+|$1| while ! -d $dir;
    opendir DIR, $dir;
    my @files;
    push @files, $_ while readdir DIR;
    closedir DIR;
    my $response = [];
    foreach (sort { -d "$dir/$a" && -f "$dir/$b" ? -1
                  : -f "$dir/$a" && -d "$dir/$b" ?  1
                  :          $a     cmp      $b     } @files) {
        next if /^\.$/;
        next if /^\.\w/;
        next if /^\.\.$/ && $dir eq "$root/";
        if ($_ eq '..') {
            push @$response, { name => $_, ops => [ qw(cd) ] };
        } elsif (-d "$dir/$_") {
            push @$response, { name => $_, ops => [ qw(cd i a A) ] };
        } else {
            push @$response, { name => $_, ops => [ qw(i a A I H J) ] };
        }
    }
    print header 'application/json';
    print encode_json $response;
}

# Browse internet radio stations
sub fm {
    (my $cmd = shift) =~ s|/|\n|g;     # /-separated from GET
    my $data = join("\n", @{shift()}); # JSON array from POST
    if ($cmd =~ /\n[iaAIHJ]/) {
        print header 'text/plain', '400 No playlist changes in GET requests';
        return;
    }
    my $cmds = $data || $cmd;
    my $response = [
        { name => '/g', ops => [ 'cd' ], label => 'Genres' },
        { name => '/m', ops => [ 'cd' ], label => 'My Stations' },
    ];
    my ($title, %list) = run_rpifm $cmds;
    push @$response, { name => $title || 'Genres', ops => [] } if %list;
    foreach (sort byalphanum keys %list) {
        unless ($title) {
            push @$response, {
                name => $_,
                ops => [ 'cd' ],
                label => $list{$_},
            };
        } elsif (/^[<>]$/) {
            push @$response, {
                name => $_,
                ops => [ 'cd' ],
                label => $_ eq '<' ? 'Previous' : 'Next',
            };
        } else {
            push @$response, {
                name => $_,
                ops => [ qw(i a A I H J) ],
                label => $list{$_},
            };
        }
    }
    print header 'application/json';
    print encode_json $response;
    rpifm_my;
}

sub run_rpifm {
    my $cmd = shift;
    my $pid = open2(\*IN, \*OUT, '/usr/bin/rpi.fm') or die $!;
    print OUT $cmd;
    close OUT;
    my ($title, %list);
    while (<IN>) {
        s/\r|\n//g;
        if (/^[a-zA-Z]/) {
            $title = $_;
            %list = ();
        } elsif (/^ *(\d+|[<>]) +(.+)$/) {
            $list{$1} = $2;
        }
    }
    close IN;
    waitpid $pid, 0;
    return $title, %list;
}

sub rpifm_my {
    return unless open RPI, ".rpi.fm";
    my $dump;
    while (<RPI>) {
        $dump .= $_ if /MyStations/ || $dump; # Lines from MysStations on
        last if $dump && /^  }/;              # until its closing brace
    }
    $dump =~ s/.+?\{/\$fm_my = {/;
    eval $dump;
}

sub byalphanum {
    return $a <=> $b if $a =~ /^\d+$/ && $b =~ /^\d+$/;
    return $a cmp $b;
}

# Browse and play YouTube
sub yt {
    (my $cmd = shift) =~ m|^([^/]+)/(.*)|;
    my ($cmd, $query) = ($1, $2);
    my $data = shift;
    # Playback command
    if ($data) {
        my @streams = WWW::U2B::extract_streams $data->{query};
        foreach (@streams) {
            next unless $_->{extension} eq 'mp4';
            WWW::U2B::playback "omxd $data->{cmd}", $_;
            logger "U2B: extension=".$_->{extension}.", quality=".$_->{quality};
            logger "omxd $data->{cmd} $_->{url}";
            last;
        }
        print header 'text/plain';
        $ytid = $data->{query};
        return;
    }
    # Search command
    my @response = WWW::U2B::search(split / /, $query);
    foreach (@response) {
        $_->{ops} = [ qw(I H J) ];
        $ythits{$_->{name}} = $_->{label};
    }
    print header 'application/json';
    print encode_json \@response;
}

sub logger {
    return if tell LOG == -1;
    my $msg = shift;
    local $| = 1; # autoflush to logfile
    print LOG "\n", time(), " PID: $$\n", $msg, "\n";
}
