#!/usr/bin/perl
#
# Module: vyatta-show-conntrack.pl
#
# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2010 Vyatta, Inc.
# All Rights Reserved.
#
# Author: Gaurav Sinha 
# Date: Oct 2011 
# Description: 	Script to show conntrack entries based on the input 
#                show command. 
#
# **** End License ****
#
use Getopt::Long;
use XML::Simple;
use Data::Dumper;
use POSIX;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Misc;
use warnings;
use strict;
use Switch;

my $format = "%-10s %-22s %-22s %-12s %-20s\n";

sub print_xml {
    my ($data, $cache) = @_;

    my $flow = 0;

    my %flowh;
    my $tcount = 0;
    while (1) {
        my $meta = 0;
        last if ! defined $data->{flow}[$flow];
        my $flow_ref = $data->{flow}[$flow];
        my $flow_type = $flow_ref->{type};
        my (%src, %dst, %sport, %dport, %proto, %protonum, $timeout_ref, $connection_id_ref, 
            $state_connection_ref);
        while (1) {
            my $meta_ref = $flow_ref->{meta}[$meta];
            last if ! defined $meta_ref;
            my $dir = $meta_ref->{direction};
            if ($dir eq 'original' or $dir eq 'reply') {
                my $l3_ref    = $meta_ref->{layer3}[0];
                my $l4_ref    = $meta_ref->{layer4}[0];
                if (defined $l3_ref) {
                    $src{$dir} = $l3_ref->{src}[0];
                    $dst{$dir} = $l3_ref->{dst}[0];
                    if (defined $l4_ref) {
                        $sport{$dir} = $l4_ref->{sport}[0];
                        $dport{$dir} = $l4_ref->{dport}[0];
                        $proto{$dir} = $l4_ref->{protoname};
                        $protonum{$dir} = $l4_ref->{protonum};
                    }
                }
            } elsif ($dir eq 'independent') {
                 $timeout_ref = $meta_ref->{timeout}[0];
                 $connection_id_ref = $meta_ref->{id}[0];
                 $state_connection_ref = $meta_ref->{state}[0];
            }
            $meta++;
        }
        my ($proto, $protonum, $in_src, $in_dst, $out_src, $out_dst, $connection_id, 
            $timeout, $state_connection);
        $proto    = $proto{original};
        $protonum = $protonum{original};
        $in_src   = "$src{original}";
        $in_src  .= ":$sport{original}" if defined $sport{original};
        $in_dst   = "$dst{original}";
        $in_dst  .= ":$dport{original}" if defined $dport{original};
        $connection_id = "$connection_id_ref";
        $timeout = "$timeout_ref";

        if ($state_connection_ref) {
            $state_connection = "$state_connection_ref";
        }

        # not using these for now
        $out_src  = "|$dst{reply}|";
        $out_src .= ":$dport{reply}" if defined $dport{reply};
        $out_dst  = "|$src{reply}|";
        $out_dst .= ":$sport{reply}" if defined $sport{reply};

        my $protocol = $proto . ' [' . $protonum . ']';
        if ($state_connection) {
            switch($state_connection) {
                case ("ESTABLISHED") {
                      $protocol .= " ES";
                   }
                case ("SYN_SENT") {
                      $protocol .= " SS";
                   }
                case ("SYN_RECV") {
                      $protocol .= " SR";
                   }
                case ("FIN_WAIT") {
                      $protocol .= " FW";
                   }
                case ("CLOSE_WAIT") {
                      $protocol .= " CW";
                   }
                case ("LAST_ACK") {
                      $protocol .= " LA";
                   }
                case ("TIME_WAIT") {
                      $protocol .= " TW";
                   }
                case ("CLOSED") {
                      $protocol .= " CL";
                   }
                case ("LISTEN") {
                      $protocol .= " LI";
                   }
            }
        }
        printf($format, $connection_id ,$in_src, $in_dst, $protocol, $timeout);
        $flow++;
    }
    return $flow;
}

#
# main
#

my ($sourceIP, $destIP, $family);

GetOptions("source_IP=s"    => \$sourceIP,
           "dest_IP=s"      => \$destIP,
           "family=s"       => \$family,
);

my $xs = XML::Simple->new(ForceArray => 1, KeepRoot => 0);
my ($xml1, $xml2, $data);

#build command string using <command_prefix><command>. 
my $command_prefix = "sudo conntrack -L";
my $command = " --family $family";

my ($sourcePort, $destPort);
if ($family eq "ipv4") {
    if ((defined $sourceIP) and $sourceIP =~ m/:/) {
        #IP address and port entered, are of the form IP:port
        my @address = split(/:/, $sourceIP);
        $sourceIP = $address[0]; 
        $sourcePort = $address[1];

        # Check if IP address is a valid IPv4 address
        my( $success, $err ) = isValidPortNumber($sourcePort);
        if (!(isIpAddress($sourceIP))and !($sourceIP eq "0.0.0.0")) {
            if(!defined($success)) {
                #both IP and port are invalid
                die "Please enter a valid source IPv4 address and port \n";
            } else {
                #only IP is invalid
                die "Please enter a valid source IPv4 address\n";
            }
        }
        if(!defined($success)) {
            #port is invalid
            die "Please enter a valid source port \n";
        }
        $command .= " --orig-port-src $sourcePort";
    }

    if ((defined $destIP) and $destIP =~ m/:/) {
        my @address = split(/:/, $destIP);
        $destIP = $address[0]; 
        $destPort = $address[1];
        my( $success, $err ) = isValidPortNumber($destPort);
        if (!(isIpAddress($destIP))and !($destIP eq "0.0.0.0")) {
            if(!defined($success)) {
                #both IP and port are invalid
                die "Please enter a valid destination IPv4 address and port \n";
            } else {
                #only IP is invalid
                die "Please enter a valid destination IPv4 address\n";
            }
        }
        if(!defined($success)) {
            #port is invalid
            die "Please enter a valid destination port \n";
        }
        $command .= " --orig-port-dst $destPort";
    }

    if ((defined $sourceIP) and !($sourceIP eq "0.0.0.0")) {
       # Check if IP address is a valid IPv4 address
       if (!(isIpAddress($sourceIP))) {
           die "Please enter a valid source IPv4 address\n";
       }
       #If IP is any, do not add anything to command.  
       $command .= " -s $sourceIP";   
    }

    if ((defined $destIP) and !($destIP eq "0.0.0.0")) {
       # Check if IP address is a valid IPv4 address
       if (!(isIpAddress($destIP))) {
           die "Please enter a valid destination IPv4 address\n";
       }
       $command .= " -d $destIP";   
    }
} else {
    #family IPv6 not supported, placeholder for v6 code.
}

$command .= " -o xml";
print "TCP state codes: SS - SYN SENT, SR - SYN RECEIVED, ES - ESTABLISHED,\n";
print "                 FW - FIN WAIT, CW - CLOSE WAIT, LA - LAST ACK,\n";
print "                 TW - TIME WAIT, CL - CLOSE, LI - LISTEN\n\n";

printf($format, 'CONN ID', 'Source', 'Destination', 'Protocol', 'TIMEOUT');
if ((defined($destPort)) or (defined($sourcePort))) {
    my $command_final = $command_prefix." -p tcp".$command; 
    $xml1 = `$command_final 2> /dev/null`; 

    #Execute the command for UDP as well. 
    $command_final = $command_prefix." -p udp".$command; 
    $xml2 = `$command_final 2> /dev/null`; 
} else {
    my $command_final = $command_prefix.$command; 
    $xml1 = `$command_final 2> /dev/null`; 
} 

if ($xml1) {
    $data = $xs->XMLin($xml1);
    print_xml($data);
}
if ($xml2) {
    $data = $xs->XMLin($xml2);
    print_xml($data);
}
# end of file
