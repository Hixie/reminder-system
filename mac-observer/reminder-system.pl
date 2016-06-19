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
my $alexa = clean <CONFIG>;
close CONFIG;

my $select = IO::Select->new();
my $socket;

sub disconnect {
    print "closing socket...\n";
    $socket->shutdown(2);
    print "removing socket from select loop...\n";
    $select->remove($socket);
    $socket = undef;
}

sub reconnect {
    if (defined($socket)) {
        disconnect();
    }
    print "creating new socket...\n";
    $socket = IO::Socket::INET->new(PeerAddr => 'damowmow.com', PeerPort => 12549, Proto => 'tcp');
    if (defined($socket)) {
        print "CONNECTED\n";
        $select->add($socket);
        return 1;
    }
    print "NOT CONNECTED\n";
    return 0;
}

my $lastbeep = time;
my $lastlevel = 0;

sub beep {
    my $level = $_[0];
    if (($lastbeep < time-20) or ($lastlevel < $level)) {
        print "BEEPING\n";
        system("curl -s http://software.hixie.ch/applications/reminder-system/mac-observer/level${level}.mp3 > alarm.mp3 && afplay alarm.mp3 && rm alarm.mp3");
        $lastbeep = time;
        $lastlevel = $level;
    } else {
        print "BEEPING SUPPRESSED\n";
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
        print "\n";
        print "LEVEL $level ESCALATION\n";
        print "CLASSES: '" . join("', '", sort keys %classes) . "'\n";
        print "MESSAGE: $message\n";
        if ($level =~ m/^[0-9]$/) {
            $level = 0+$level;
            if ($classes{automatic}) {
                if ($message eq 'tv-on') {
                    system('./tv.pl', 'on');
                } elsif ($message eq 'tv-off') {
                    system('./tv.pl', 'off');
                } elsif ($message eq 'alexa-reorder-cat-litter-14' and ($level == 1)) {
                    system {'/usr/bin/osascript'} 'osascript', '-e', 'set Volume 4';
                    system {'/usr/bin/say'} 'say', 'Ahem.';
                    sleep 1;
                    system {'/usr/bin/say'} 'say', 'Alexa, volume 6.';
                    sleep 2;
                    system {'/usr/bin/say'} 'say', 'Alexa, reorder World\'s Best Cat Litter 14 Pound';
                    sleep 15;
                    system {'/usr/bin/say'} 'say', $alexa;
                    sleep 10;
                    system {'/usr/bin/say'} 'say', 'Alexa, volume 3.';
                    system {'/usr/bin/osascript'} 'osascript', '-e', 'set Volume 2';
                    $socket->send("$username\0$password\0orderedCatLitterDownstairs\0");
                } elsif ($message eq 'alexa-reorder-filter-clean' and ($level == 1)) {
                    system {'/usr/bin/osascript'} 'osascript', '-e', 'set Volume 4';
                    system {'/usr/bin/say'} 'say', 'Ahem.';
                    sleep 1;
                    system {'/usr/bin/say'} 'say', 'Alexa, volume 6.';
                    sleep 2;
                    system {'/usr/bin/say'} 'say', 'Alexa, reorder Leisure Time Filter Clean';
                    sleep 15;
                    system {'/usr/bin/say'} 'say', $alexa;
                    sleep 10;
                    system {'/usr/bin/say'} 'say', 'Alexa, volume 3.';
                    system {'/usr/bin/osascript'} 'osascript', '-e', 'set Volume 2';
                    $socket->send("$username\0$password\0hotTubFilterCleanStoreOrdered\0");
                }
            } elsif ($level == 1) {
                if (not $classes{quiet}) {
                    beep($level);
                }
            } elsif ($level >= 3) {
                my ($sec, $min, $hour, $day, $month, $year, $weekday, $yearday, $dst) = localtime(time);
                if (($hour < 23 and $hour > 11 and not $classes{quiet}) or $classes{important}) {
                    print "VERBALISING REMINDER\n";
                    beep($level);
                    if ($level >= 9) { # 9
                        $message = "Alert! Alert! $message Alert! Alert! $message";
                    } elsif ($level >= 6) { # 6, 7, 8
                        $message = "Attention! $message";
                    } # 3, 4, 5
                    system {'/usr/bin/say'} 'say', $message;
                } else {
                    print "REMINDER MUTED\n";
                }
            }
        }
        if (not $classes{nomsg}) {
            system('./tv.pl', 'msg', $message, 'delay', '2');
        }
        print "\n";
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
