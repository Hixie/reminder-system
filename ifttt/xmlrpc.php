#!/usr/bin/perl -wT
use strict;
use IO::Socket;

local $/ = undef;
my $input = <>;

die unless $ENV{REQUEST_METHOD} eq 'POST';

use XML::Simple;
my $data = XMLin($input);

if ($data->{methodName} eq 'mt.supportedMethods') {
    print STDOUT "Status: 200 OK\r\nContent-Type: text/xml\r\n\r\n<?xml version=\"1.0\"?><methodResponse><params><param><value>metaWeblog.getRecentPosts</value></param></params></methodResponse>\n";
} elsif ($data->{methodName} eq 'metaWeblog.getRecentPosts') {
    my $username = $data->{params}->{param}->[1]->{value}->{string};
    my $password = $data->{params}->{param}->[2]->{value}->{string};
    print STDOUT "Status: 200 OK\r\nContent-Type: text/xml\r\n\r\n<?xml version=\"1.0\"?><methodResponse><params><param><value><array><data></data></array></value></param></params></methodResponse>\n";
} elsif ($data->{methodName} eq 'metaWeblog.newPost') {
    my $username = $data->{params}->{param}->[1]->{value}->{string};
    my $password = $data->{params}->{param}->[2]->{value}->{string};
    my $title = $data->{params}->{param}->[3]->{value}->{struct}->{member}->{title}->{value}->{string};
    my $body = $data->{params}->{param}->[3]->{value}->{struct}->{member}->{description}->{value}->{string};
    doSomething($username, $password, $title, $body);
    print STDOUT "Status: 200 OK\r\nContent-Type: text/xml\r\n\r\n<?xml version=\"1.0\"?><methodResponse><params><param><value><string>200</string></value></param></params></methodResponse>\n";
} else {
    print STDOUT "Status: 400 Nope\r\nContent-Type: text/plain\r\n\r\nNope.\n";
}

sub doSomething {
    my($username, $password, $command, $body) = @_;
    print STDERR "USERNAME: $username\nPASSWORD: $password\nCOMMAND: $command\nBODY: $body\n";
    die if $username =~ m/\0/os;
    die if $password =~ m/\0/os;
    die if $command =~ m/\0/os;
    die if $body =~ m/\0/os;
    if ($command eq 'remy') {
        pushButton($username, $password, $body);
    } elsif ($command eq 'google') {
        if ($body eq 'wet-food') {
            my($seconds, $minutes, $hours, $day, $month, $year, $weekday, $dayOfYear, $summerTime) = localtime(time);
            if ($hours > 4 and $hours < 17) {
                pushButton($username, $password, 'catFedSmallCanForBreakfast');
            } else {
                pushButton($username, $password, 'catFedSmallCanForDinner');
            }
        } elsif ($body =~ m/^push *(?:the)? *button (.+)$/i or
                 $body =~ m/^push *(?:the)? *(.+) *button$/i) {
            my $todo = "\L$1";
            my @words = split(' ', $todo);
            if ($words[0] eq 'the') {
                shift @words;
            }
            my $button = join('', map { "\u$_" } @words);
            $button = "\l$button";
            warn("trying to push button '$button'");
            pushButton($username, $password, $button);
        } else {
            warn "unknown 'google' message ('$body')";
        }
    } else {
        die "unknown command ('$command')";
    }
}

sub pushButton {
    my($username, $password, $button) = @_;
    my $socket = IO::Socket::INET->new(PeerAddr => 'damowmow.com', PeerPort => 12549, Proto => 'tcp') or die "connect failed $!";
    print $socket "$username\0$password\0$button\0\0\0";
    close $socket;
}