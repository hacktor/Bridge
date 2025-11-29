package Hermod;

use JSON;
use TOML;
use WWW::Curl::Easy;
use WWW::Curl::Form;
use URI::Escape;
use Capture::Tiny 'capture';
use Encode qw(encode_utf8);
use LWP::UserAgent;
use IO::Socket::INET;

sub bridge {

    my ($msg,$cfg) = @_;
    return "missing fields in message\n"
        unless $msg->{user} and $msg->{prefix} and $msg->{text} and $msg->{token} and $msg->{chat};

    my $json;
    eval {
        $json = encode_json $msg;
    };
    return "Error in encode_json, sub bridge\n" if $@;

    # auto-flush on socket
    $| = 1;

    # create a connecting socket
    my $socket = new IO::Socket::INET (
        PeerHost => '127.0.0.1',
        PeerPort => (defined $cfg->{common}{port}) ? $cfg->{common}{port} : '31337',
        Proto => 'tcp',
    );
    return "cannot connect to the server $!\n" unless $socket;

    my $send = $socket->send($json);
    $socket->shutdown(SHUT_RDWR);
    return $json;
}

sub getmmlink {

    my ($id,$mm,$dbg) = @_;
    return unless defined $mm;
    my $json = JSON->new->allow_nonref;
    my $ua = LWP::UserAgent->new;

    my $info_res = $ua->get( "$mm->{api}/files/$id/info", 'Authorization' => "Bearer $mm->{bearer}");
    unless $info_res->is_success {
        print $dbg "Kon file info niet ophalen: " . $info_res->status_line if defined $dbg;
        return;
    }
    my $info = decode_json($info_res->decoded_content);
    my $file_res = $ua->get( "$mm->{api}/files/$id", 'Authorization' => "Bearer $mm->{bearer}");
    unless $file_res->is_success {
        print $dbg "Kon file niet downloaden: " . $file_res->status_line if defined $dbg;
        return;
    }
    open my $fh, ">", "$mm->{attachments}/$info->{name}" or return;
    binmode $fh;
    print $fh $file_res->decoded_content;
    close $fh;
    return "$mm->{attachurl}/$info->{name}";
}

sub relay2mm {

    my ($text,$mm,$dbg) = @_;
    return unless defined $mm;

    my $json = JSON->new->allow_nonref;
    $text = $json->encode({attachments => [{text => $text}], username => $mm->{user_name}});

    my $curl = WWW::Curl::Easy->new;
    my $response_body;
    $curl->setopt(CURLOPT_WRITEDATA,\$response_body);
    $curl->setopt(CURLOPT_URL, $mm->{url});
    $curl->setopt(WWW::Curl::Easy::CURLOPT_NOPROGRESS(), 1);
    $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(), ['Content-Type: application/json; charset=UTF-8']);
    $curl->setopt(WWW::Curl::Easy::CURLOPT_POST(), 1);
    $curl->setopt(WWW::Curl::Easy::CURLOPT_POSTFIELDS, $text);
    $curl->setopt(CURLOPT_SSL_VERIFYPEER, 0);  # don’t verify cert against CA
    $curl->setopt(CURLOPT_SSL_VERIFYHOST, 0);  # don’t check hostname in cert
    my $retcode = $curl->perform;
    if ($retcode != 0) {
        print $dbg "An error happened: $retcode ".$curl->strerror($retcode)." ".$curl->errbuf."\n" if $dbg;
    }
}

sub relayFile2mm {

    my ($line,$mm,$dbg) = @_;
    return unless defined $mm;
    if ($line =~ /^FILE!/) {

        $line = substr $line,5;
        my ($fileinfo,$caption) = split / /, $line, 2;
        my ($url,$mime,$file) = split /!/, $fileinfo;

        my $json = JSON->new->allow_nonref;
        my $bearer = "Authorization: Bearer $mm->{bearer}";

        my ($out, $err, $ret) = capture {
            system("curl", "-s", "-XPOST", "-H", "$bearer", "-F", "channel_id=$mm->{channel_id}", "-F", "files=\@$file", "$mm->{api}/files" );
        };
        print $dbg $out, $err if defined $dbg;

        my $jsonret;
        eval { $jsonret = $json->decode($out); };
        print $dbg $@ if defined $dbg and $@;

        if (defined $jsonret->{file_infos} and ref $jsonret->{file_infos} eq "ARRAY") {

            my $jh = {
                channel_id => $mm->{channel_id},
                message => $caption,
                file_ids => [ $jsonret->{file_infos}[0]{id} ]
            };
            my $jsonstr = $json->encode($jh);
            my $curl = WWW::Curl::Easy->new;
            my $response_body;
            $curl->setopt(CURLOPT_WRITEDATA,\$response_body);
            $curl->setopt(CURLOPT_URL, "$mm->{api}/posts");
            $curl->setopt(WWW::Curl::Easy::CURLOPT_NOPROGRESS(), 1);
            $curl->setopt(WWW::Curl::Easy::CURLOPT_VERBOSE, 0);
            $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(), ['Content-Type: application/json; charset=UTF-8', $bearer]);
            $curl->setopt(WWW::Curl::Easy::CURLOPT_POST(), 1);
            $curl->setopt(WWW::Curl::Easy::CURLOPT_POSTFIELDS, $jsonstr);
            $curl->setopt(CURLOPT_SSL_VERIFYPEER, 0);  # don’t verify cert against CA
            $curl->setopt(CURLOPT_SSL_VERIFYHOST, 0);  # don’t check hostname in cert
            my $retcode = $curl->perform;
            if ($retcode != 0) {
                print "An error happened: $retcode ".$curl->strerror($retcode)." ".$curl->errbuf."\n";
            }
            print "Response: $response_body\n";
        }

    }
}

sub relay2mtx {

    my ($line,$mat,$dbg) = @_;
    return unless defined $mat;

    # we relay straight to matrix
    (my $posturl = $mat->{posturl}) =~ s/__ROOM__/$mat->{room}/;
    $posturl =~ s/__TOKEN__/$mat->{token}/;

    if ($line =~ /^FILE!/) {

        # send photo's, documents
        $line = substr $line,5; 
        my ($fileinfo,$caption) = split / /, $line, 2;
        my ($url,$mime,$filepath) = split /!/, $fileinfo;

        # TODO upload file
        next;
    }

    chomp $line;
    $line =~ s/"/\\"/g;
    $line =~ s/\n/\\n/g;
    my $body = '{"msgtype":"m.text", "body":"'.$line.'"}';
    print $dbg "body: $body\n" if defined $dbg;
    my ($out, $err, $ret) = capture {
        system("curl", "-s", "-XPOST", "-d", "$body", "$posturl");
    };
    print $dbg $out, $err if defined $dbg;
}

sub relay2tel {

    my ($tel,$text,$dbg) = @_;
    return unless defined $tel;

    # we relay straight to telegram
    my $telmsg;
    $text = encode_utf8($text);
    eval { $telmsg = uri_escape($text); };
    $telmsg = uri_escape_utf8($text) if $@;
    my ($out, $err, $ret) = capture {
        system("curl", "-s", "https://api.telegram.org/bot$tel->{token}/sendMessage?chat_id=$tel->{chat_id}&text=$telmsg");
    };
    print $dbg $out, $err if defined $dbg;
}

sub relayFile2tel {

    my ($line,$tel,$type,$dbg) = @_;
    return unless defined $tel;
    if ($line =~ /^FILE!/ and $tel->{token} and $tel->{chat_id} and $type) {

        $line = substr $line,5;
        my ($fileinfo,$caption) = split / /, $line, 2;
        my ($url,$mime,$file) = split /!/, $fileinfo;

        my $URL = ($type eq "photo") ? "https://api.telegram.org/bot$tel->{token}/sendPhoto"
                                     : "https://api.telegram.org/bot$tel->{token}/sendDocument";

        my $curl = WWW::Curl::Easy->new;
        $curl->setopt(CURLOPT_URL, $URL);
        my $curlf = WWW::Curl::Form->new;
        $curlf->formaddfile($file, $type, "multipart/form-data");
        $curlf->formadd("chat_id", "$tel->{chat_id}");
        $curlf->formadd("caption", $caption);
        $curl->setopt(CURLOPT_HTTPPOST, $curlf);
        my $retcode = $curl->perform;
        if ($retcode != 0) {
            print $dbg "An error happened in relayFile2tel: $retcode ".$curl->strerror($retcode)." ".$curl->errbuf."\n" if defined $dbg;
        }
    }
}

sub relay2dis {

    my ($text,$dis,$dbg) = @_;
    return unless defined $dis;

    # we relay straight to discord
    my $json = JSON->new->allow_nonref;
    my $dismsg = {
        username => $dis->{username},
        content => $text,
    };
    $text = $json->encode($dismsg);
    my ($out, $err, $ret) = capture {
        system("curl", "-s", "-H", "Content-Type: application/json", "-d", "$text", "$dis->{webhook}");
    };
    print $dbg $out, $err if defined $dbg;
}

sub relay2irc {

    my ($text,$irc,$pre,$dbg) = @_;
    return unless defined $irc;
    return unless $irc->{infile} and $text;

    my @lines = split /\n/, $text;
    open my $w, ">>:utf8", $irc->{infile} or return;
    for my $msg (@lines) {

        next unless $msg;

        # send to IRC, split lines in chunks of ~maxmsg size if necessary
        if (length $msg > $irc->{maxmsg}) {
            $msg =~ s/(.{1,$irc->{maxmsg}}\S|\S+)\s+/$1\n/g;
            eval { print $w "$pre$_\n" for split /\n/, $msg; };
            print $dbg $@ if $@ and defined $dbg;
        } else {
            eval { print $w "$pre$msg\n"; };
            print $dbg $@ if $@ and defined $dbg;
        }
    }
    close $w;
}

sub relayToFile {

    my ($line,$infile,$dbg) = @_;
    return unless $infile and $line;
    open my $w, ">>:utf8", $infile;
    print $w $line if defined $w;
    close $w;
}

sub relay2sig {
    my ($line,$sig,$dbg) = @_;
    return unless defined $sig;
    return unless $line;

    # revert to old behaviour unless we defined signal->transport->dbus
    if (not defined $sig->{transport} or $sig->{transport} =~ /file/i) {
        relayToFile($line,$sig->{infile},$dbg);
    }

    my $text = '';
    if ($line =~ /^FILE!/) {

        # send photo's, documents
        $line = substr $line,5;
        my ($fileinfo,$caption) = split / /, $line, 2;
        my ($url,$mime,$file) = split /!/, $fileinfo;
        my ($out, $err, $ret) = capture {
            system($sig->{cli},"--dbus","send","-g",$sig->{gid},"-m","$caption","-a","$file");
        };
        print $dbg $out, $err if defined $dbg;

    } else {

        my $text = ''; my $sav = $line;
        eval { $text .= decode_utf8($msg, Encode::FB_QUIET) while $line; };
        $text = $sav if $@; # try undecoded string as last resort

        my ($out, $err, $ret) = capture {
            system($sig->{cli},"--dbus","send","-g",$sig->{gid},"-m","$text");
        };
        print $dbg $out, $err if defined $dbg;
    }
}

1;
