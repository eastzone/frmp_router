#!/usr/bin/perl

use strict;
use NF2::RegressLib;
use NF2::PacketLib;
use RegressRouterLib;

use reg_defines_cs344_starter;

my @interfaces = ("nf2c0", "nf2c1", "nf2c2", "nf2c3", "eth1", "eth2");
nftest_init(\@ARGV,\@interfaces,);
nftest_start(\@interfaces);

nftest_fpga_reset('nf2c0');

my $routerMAC0 = "00:ca:fe:00:00:01";
my $routerMAC1 = "00:ca:fe:00:00:02";
my $routerMAC2 = "00:ca:fe:00:00:03";
my $routerMAC3 = "00:ca:fe:00:00:04";

my $routerIP0 = "192.168.0.40";
my $routerIP1 = "192.168.1.40";
my $routerIP2 = "192.168.2.40";
my $routerIP3 = "192.168.3.40";

for (my $i = 0; $i < 32; $i++)
{
  nftest_invalidate_LPM_table_entry('nf2c0', $i);
  nftest_invalidate_ARP_table_entry('nf2c0', $i);
  nftest_invalidate_dst_ip_filter_entry ('nf2c0', $i);
  nftest_regwrite('nf2c0', ROUTER_OP_LUT_GATEWAY_TABLE_ENTRY_IP_REG(), 0xffffffff);#$nextHopIP = "192.168.1.54";
  nftest_regwrite('nf2c0', ROUTER_OP_LUT_GATEWAY_TABLE_WR_ADDR_REG(), $i);
}

# Write the mac and IP addresses
nftest_add_dst_ip_filter_entry ('nf2c0', 0, $routerIP0);
nftest_add_dst_ip_filter_entry ('nf2c1', 1, $routerIP1);
nftest_add_dst_ip_filter_entry ('nf2c2', 2, $routerIP2);
nftest_add_dst_ip_filter_entry ('nf2c3', 3, $routerIP3);

nftest_set_router_MAC ('nf2c0', $routerMAC0);
nftest_set_router_MAC ('nf2c1', $routerMAC1);
nftest_set_router_MAC ('nf2c2', $routerMAC2);
nftest_set_router_MAC ('nf2c3', $routerMAC3);

nftest_regwrite('nf2c0', 0x0440060, 0xf0c7);
nftest_regwrite('nf2c0', 0x04400e0, 0xf0c7);
nftest_regwrite('nf2c0', 0x0440160, 0xf0c7);
nftest_regwrite('nf2c0', 0x04401e0, 0xf0c7);

# add an entry in the routing table:
my $index = 0;
my $subnetIP = "192.168.2.0";
my $subnetIP2 = "192.168.1.0";
my $subnetMask = "255.255.255.0";
my $subnetMask2 = "255.255.255.0";
my $nextHopIP = "192.168.1.54";
my $nextHopIP2 = "192.168.3.12";
my $outPort = 0x1; # output on MAC0
my $outPort2 = 0x4;
my $nextHopMAC = "dd:11:dd:22:dd:33";
my $nextHopMAC2 = "dd:55:dd:66:dd:77";

my $MAC_hdr2;

nftest_regwrite('nf2c0', ROUTER_OP_LUT_ROUTE_TABLE_ENTRY_IP_REG(), 0xc0a80100);#$subnetIP2 = "192.168.1.0";
nftest_regwrite('nf2c0', ROUTER_OP_LUT_ROUTE_TABLE_ENTRY_MASK_REG(), 0xffffff00);
nftest_regwrite('nf2c0', ROUTER_OP_LUT_ROUTE_TABLE_ENTRY_OUTPUT_PORT_REG(), 0x5);
nftest_regwrite('nf2c0', ROUTER_OP_LUT_ROUTE_TABLE_ENTRY_NEXT_HOP_IP_REG(), 0x0201);
nftest_regwrite('nf2c0', ROUTER_OP_LUT_GATEWAY_TABLE_ENTRY_IP_REG(), 0xc0a80136);#$nextHopIP = "192.168.1.54";
nftest_regwrite('nf2c0', ROUTER_OP_LUT_GATEWAY_TABLE_WR_ADDR_REG(), 1);
nftest_regwrite('nf2c0', ROUTER_OP_LUT_GATEWAY_TABLE_ENTRY_IP_REG(), 0xc0a8030c);#$nextHopIP2 = "192.168.3.12";
nftest_regwrite('nf2c0', ROUTER_OP_LUT_GATEWAY_TABLE_WR_ADDR_REG(), 2);
nftest_regwrite('nf2c0', ROUTER_OP_LUT_ROUTE_TABLE_WR_ADDR_REG(), 1);

# add an entry in the ARP table
nftest_add_ARP_table_entry('nf2c0',
			   1,
			   $nextHopIP,
			   $nextHopMAC);

# add an entry in the ARP table
nftest_add_ARP_table_entry('nf2c0',
			   2,
			   $nextHopIP2,
			   $nextHopMAC2);

my $total_errors = 0;
my $temp_error_val = 0;

#clear the num pkts forwarded reg
nftest_regwrite('nf2c0', ROUTER_OP_LUT_NUM_PKTS_FORWARDED_REG(), 0);
nftest_regwrite('nf2c0', ROUTER_OP_LUT_FAST_REROUTE_ENABLE_REG(), 0);
nftest_regwrite('nf2c0', ROUTER_OP_LUT_MULTIPATH_ENABLE_REG(), 1);

# loop for 20 packets from eth1 to eth2
for (my $i = 0; $i < 20; $i++)
{
	# set parameters
	my $DA = $routerMAC0;
	my $SA = "aa:bb:cc:dd:ee:ff";
	my $TTL = 64;
	my $DST_IP = "192.168.1.1"; 
	my $SRC_IP = "192.168.0.1";
	my $len = 100;
	#my $nextHopMAC = "dd:55:dd:66:dd:77";

	# create mac header
	my $MAC_hdr = NF2::Ethernet_hdr->new(DA => $DA,
						     SA => $SA,
						     Ethertype => 0x800
				    		);

	#create IP header
	my $IP_hdr = NF2::IP_hdr->new(ttl => $TTL,
					      src_ip => $SRC_IP,
					      dst_ip => $DST_IP
			    		 );

	$IP_hdr->checksum(0);  # make sure its zero before we calculate it.
	$IP_hdr->checksum($IP_hdr->calc_checksum);

	# create packet filling.... (IP PDU)
	my $PDU = NF2::PDU->new($len - $MAC_hdr->length_in_bytes() - $IP_hdr->length_in_bytes() );
	my $start_val = $MAC_hdr->length_in_bytes() + $IP_hdr->length_in_bytes()+1;
	my @data = ($start_val..$len);
	for (@data) {$_ %= 100}
	$PDU->set_bytes(@data);

	# get packed packet string
	my $sent_pkt = $MAC_hdr->packed . $IP_hdr->packed . $PDU->packed;

	# create the expected packet
	if($i%2==0){
	 	$MAC_hdr2 = NF2::Ethernet_hdr->new(DA => $nextHopMAC,
						     SA => $routerMAC0,
						     Ethertype => 0x800
				    		);
	}
	else{
	 	$MAC_hdr2 = NF2::Ethernet_hdr->new(DA => $nextHopMAC2,
						     SA => $routerMAC1,
						     Ethertype => 0x800
				    		);
	}

	$IP_hdr->ttl($TTL-1);
	$IP_hdr->checksum(0);  # make sure its zero before we calculate it.
	$IP_hdr->checksum($IP_hdr->calc_checksum);

	my $expected_pkt = $MAC_hdr2->packed . $IP_hdr->packed . $PDU->packed;

	# send packet out of eth1->nf2c0 
	nftest_send('eth1', $sent_pkt);
	if($i%2==0) {nftest_expect('eth1', $expected_pkt);}
	else {nftest_expect('eth2', $expected_pkt);}
  `usleep 500`;
}


sleep 1;
for (my $i = 0; $i < 32; $i++)
{
  nftest_invalidate_LPM_table_entry('nf2c0', $i);
  nftest_invalidate_ARP_table_entry('nf2c0', $i);
  nftest_invalidate_dst_ip_filter_entry ('nf2c0', $i);
}

nftest_regwrite('nf2c0', ROUTER_OP_LUT_FAST_REROUTE_ENABLE_REG(), 0);
nftest_regwrite('nf2c0', ROUTER_OP_LUT_MULTIPATH_ENABLE_REG(), 0);
my $unmatched_hoh = nftest_finish();
nftest_reset_phy();
$total_errors += nftest_print_errors($unmatched_hoh);

$temp_error_val += nftest_regread_expect('nf2c0', ROUTER_OP_LUT_NUM_PKTS_FORWARDED_REG, 20);

if ($temp_error_val == 20 && $total_errors == 0) {
  print "SUCCESS!\n";
	exit 0;
}
elsif ($temp_error_val != 20) {
  print "Expected 20 packets forwarded. Forwarded $temp_error_val\n";
	exit 1;
}
else {
	print "Failed: $total_errors errors\n";	
	exit 1;
}

