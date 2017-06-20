#!/usr/bin/perl -wT
use strict;
use IO::Select;
use IO::Socket;
use Carp;

$ENV{PATH} = '/usr/bin:/bin';

sub clean($) {
    my($s) = @_;
    $s =~ m/^(.+)\n$/os;
    return $1;
}

open(CONFIG, '<:utf8', '.config') or die $!;
my $username = clean <CONFIG>;
my $password = clean <CONFIG>;
my $alexaCode = clean <CONFIG>;
my $hotword = clean <CONFIG>;
close CONFIG;

my $select = IO::Select->new();
my $socket;

sub disconnect {
    print "reminder-system: closing socket...\n";
    $socket->shutdown(2);
    print "reminder-system: removing socket from select loop\n";
    $select->remove($socket);
    $socket = undef;
}

sub reconnect {
    if (defined($socket)) {
        disconnect();
    }
    print "reminder-system: creating new socket...\n";
    $socket = IO::Socket::INET->new(PeerAddr => 'damowmow.com', PeerPort => 12549, Proto => 'tcp');
    if (defined($socket)) {
        print "reminder-system: connected to reminder system\n";
        $select->add($socket);
        return 1;
    }
    print "reminder-system: not connected to reminder system\n";
    return 0;
}

my $lastbeep = time;
my $lastlevel = 0;

sub beep {
    my $level = $_[0];
    if (($lastbeep < time-20) or ($lastlevel < $level)) {
        print "reminder-system: beeping\n";
        system("curl -s http://software.hixie.ch/applications/reminder-system/mac-observer/level${level}.mp3 > alarm.mp3 && afplay alarm.mp3 && rm alarm.mp3");
        $lastbeep = time;
        $lastlevel = $level;
    } else {
        print "reminder-system: beeping suppressed\n";
    }
}

my $buffer = '';
sub process {
    $buffer .= $_[0];
    # XXX remove dupes
    while ($buffer =~ s/^(.*?)\0\0\0//os) {
        my $data = $1;
        next if $data eq '';
        my($level, $message, $classes) = split('\0', $data);
        my %classes = map { $_ => 1 } split(' ', $classes);
        print "reminder-system: \"$message\" (escalation level $level, classes: '" . join("', '", sort keys %classes) . "')\n";
        if ($level =~ m/^[0-9]$/) {
            $level = 0+$level;
            if ($classes{automatic}) {
                if ($message eq 'tv-on') {
                    system('./tv.pl', 'on');
                    $socket->send("$username\0$password\0tvOn\0\0\0");
                } elsif ($message eq 'tv-off') {
                    system('./tv.pl', 'off');
                    $socket->send("$username\0$password\0tvOff\0\0\0");
                } elsif ($message =~ m/^tv-input (hdmi([1234]))$/) {
                    my $inputName = $1;
                    system('./tv.pl', 'retry-input', $inputName);
                    $socket->send("$username\0$password\0tvInput\u$inputName\0\0\0");
                } elsif ($message =~ m/^tv-on-input (hdmi([1234]))$/) {
                    my $inputName = $1;
                    system('./tv.pl', 'on', 'retry-input', $inputName);
                    $socket->send("$username\0$password\0tvOn\0\0\0$username\0$password\0tvInput\u$inputName\0\0\0");
                } elsif ($message eq 'alexa-reorder-cat-litter-14' and ($level == 1)) {
                    buy('World\'s Best Cat Litter 14 Pound');
                    $socket->send("$username\0$password\0orderedCatLitterDownstairs\0\0\0");
                } elsif ($message eq 'alexa-reorder-filter-clean' and ($level == 1)) {
                    buy('Leisure Time Filter Clean');
                    $socket->send("$username\0$password\0hotTubFilterCleanStoreOrdered\0\0\0");
                } elsif ($message =~ m/^wake-on-lan ([0-9a-f]{12})$/ and ($level == 1)) {
                    my $mac_addr = $1;
                    my $host = '255.255.255.255';
                    my $port = 9;
                    my $sock = new IO::Socket::INET(Proto => 'udp') || die;
                    my $ip_addr = inet_aton($host);
                    my $sock_addr = sockaddr_in($port, $ip_addr);
                    my $packet = pack('C6H*', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, $mac_addr x 16);
                    setsockopt($sock, SOL_SOCKET, SO_BROADCAST, 1);
                    send($sock, $packet, 0, $sock_addr);
                    close($sock);
                }
            } elsif ($level == 1) {
                if (not $classes{quiet}) {
                    beep($level);
                }
            } elsif ($level >= 3) {
                my ($sec, $min, $hour, $day, $month, $year, $weekday, $yearday, $dst) = localtime(time);
                if (($hour < 23 and $hour > 11 and not $classes{quiet}) or $classes{important}) {
                    print "reminder-system: verbalising reminder\n";
                    beep($level);
                    if ($level >= 9) { # 9
                        $message = "Alert! Alert! $message Alert! Alert! $message";
                    } elsif ($level >= 6) { # 6, 7, 8
                        $message = "Attention! $message";
                    } # 3, 4, 5
                    system {'/usr/bin/say'} 'say', $message;
                } else {
                    print "reminder-system: reminder muted\n";
                }
            }
        }
        if (not $classes{nomsg}) {
            system('./tv.pl', 'msg', $message, 'delay', '2');
        }
    }
}

while (1) {
    while ((not defined $socket) or (not $socket->connected)) {
        reconnect() or sleep 5;
    }
    my @ready;
    if (@ready = $select->can_read(60)) {
        die "unexpected status! [@ready]" unless @ready == 1 and $ready[0] == $socket;
        my $data;
        $socket->recv($data, 1024);
        if (length $data > 0) {
            process($data);
        } else {
            disconnect();
        }
    } else {
        $socket->send("\0\0\0");
    }
}

sub buy {
    my($product) = @_;
    system {'/usr/bin/osascript'} 'osascript', '-e', 'set Volume 6';
    system {'/usr/bin/say'} 'say', 'Ahem.';
    sleep 1;
    system {'/usr/bin/say'} 'say', "$hotword, volume 6.";
    sleep 2;
    system {'/usr/bin/say'} 'say', "$hotword, reorder $product";
    sleep 20; # "Based on Ian's order history, I found ..product.. It's ..price... Would you like to buy it?"
    system {'/usr/bin/say'} 'say', "yes";
    sleep 5; # "To order it, tell me Ian's voice code."
    system {'/usr/bin/say'} 'say', $alexaCode;
    sleep 10;
    system {'/usr/bin/say'} 'say', "$hotword, volume 3.";
    system {'/usr/bin/osascript'} 'osascript', '-e', 'set Volume 2';
}