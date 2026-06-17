#!/usr/bin/perl
use strict;
use warnings;
use IO::Socket::INET;
use MIME::Base64;
use JSON::PP;

my $js_path = shift or exit 1;
my $mid = 1;

sub rx {
    my ($s, $n) = @_;
    my $b = "";
    while (length($b) < $n) { sysread($s, my $c, $n - length($b)); $b .= $c; }
    $b;
}

sub rv {
    my $s = shift;
    rx($s, 1);
    my $b = ord(rx($s, 1));
    my $l = $b & 127;
    $l = unpack("n", rx($s, 2)) if $l == 126;
    rx($s, $l);
}

sub ws {
    my ($s, $t) = @_;
    my $l = length($t);
    my @m = map { int(rand(256)) } 1..4;
    my $h = $l < 126 ? pack("CC", 0x81, 0x80 | $l) : pack("CCn", 0x81, 0xfe, $l);
    syswrite($s, $h . pack("C4", @m) .
        join("", map { chr(ord(substr($t, $_, 1)) ^ $m[$_ % 4]) } 0 .. $l - 1));
}

sub cdp {
    my ($s, $m, $p, $sid) = @_;
    my $id = $mid++;
    my %c = (id => $id, method => $m, params => ($p // {}));
    $c{sessionId} = $sid if $sid;
    ws($s, encode_json(\%c));
    while (1) {
        my $r = decode_json(rv($s));
        return $r if defined $r->{id} && $r->{id} == $id;
    }
}

my $ver;
for (1..30) {
    $ver = `curl -s http://localhost:9222/json/version 2>/dev/null`;
    last if $ver =~ /webSocketDebuggerUrl/;
    sleep 2;
}
exit 1 unless $ver =~ /"webSocketDebuggerUrl"\s*:\s*"([^"]+)"/;

my $ws_url = $1;
my ($host, $port, $path) = $ws_url =~ m!ws://([^:/]+):(\d+)(/.+)! or exit 1;

my $s = IO::Socket::INET->new(PeerHost => $host, PeerPort => $port, Proto => "tcp", Timeout => 15) or exit 1;
$s->autoflush(1);

my $k = encode_base64(join("", map { chr(int(rand(256))) } 1..16), "");
syswrite($s,
    "GET $path HTTP/1.1\r\nHost: $host:$port\r\nUpgrade: websocket\r\n" .
    "Connection: Upgrade\r\nSec-WebSocket-Key: $k\r\nSec-WebSocket-Version: 13\r\n\r\n"
);

my $r = "";
while ($r !~ /\r\n\r\n$/) { $r .= rx($s, 1); last if length($r) > 4096; }
exit 1 unless $r =~ /101/;

my $tid;
my $tgts = cdp($s, "Target.getTargets", {});
for my $t (@{$tgts->{result}{targetInfos} // []}) {
    $tid = $t->{targetId} if $t->{url} =~ /terminal/i;
}
unless ($tid) {
    my $cr = cdp($s, "Target.createTarget", { url => "chrome-untrusted://terminal/" });
    $tid = $cr->{result}{targetId};
}
exit 1 unless $tid;

my $ar  = cdp($s, "Target.attachToTarget", { targetId => $tid, flatten => JSON::PP::true() });
my $sid = $ar->{result}{sessionId} or exit 1;

open my $fh, "<", $js_path or exit 1;
local $/;
my $code = <$fh>;
close $fh;

cdp($s, "Runtime.evaluate",
    { expression => "localStorage.setItem('t'," . encode_json($code) . ")", returnByValue => JSON::PP::true() }, $sid);
cdp($s, "Page.reload", {}, $sid);
