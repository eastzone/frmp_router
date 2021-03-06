#!/usr/local/bin/perl -w
# make_pkts.pl
#
#

use NF2::PacketGen;
use NF2::PacketLib;
use SimLib;
use RouterLib;

use reg_defines_cs344_starter;

$delay = 2000;
$batch = 0;
nf_set_environment( { PORT_MODE => 'PHYSICAL', MAX_PORTS => 4 } );

# use strict AFTER the $delay, $batch and %reg are declared
use strict;
use vars qw($delay $batch %reg);

my $ROUTER_PORT_1_MAC = '00:ca:fe:00:00:01';
my $ROUTER_PORT_2_MAC = '00:ca:fe:00:00:02';
my $ROUTER_PORT_3_MAC = '00:ca:fe:00:00:03';
my $ROUTER_PORT_4_MAC = '00:ca:fe:00:00:04';

my $ROUTER_PORT_1_IP = '192.168.1.1';
my $ROUTER_PORT_2_IP = '192.168.2.1';
my $ROUTER_PORT_3_IP = '192.168.3.1';
my $ROUTER_PORT_4_IP = '192.168.4.1';

my $next_hop_1_DA = '00:fe:ed:01:d0:65';
my $next_hop_2_DA = '00:fe:ed:02:d0:65';
my $next_hop_3_DA = '00:fe:ed:03:d0:65';
my $next_hop_4_DA = '00:fe:ed:04:d0:65';

# Prepare the DMA and enable interrupts
prepare_DMA('@3.9us');
enable_interrupts(0);

# Write the ip addresses and mac addresses, routing table, filter, ARP entries
$delay = '@4us';
set_router_MAC(1, $ROUTER_PORT_1_MAC);
$delay = 0;
set_router_MAC(2, $ROUTER_PORT_2_MAC);
set_router_MAC(3, $ROUTER_PORT_3_MAC);
set_router_MAC(4, $ROUTER_PORT_4_MAC);

add_dst_ip_filter_entry(0,$ROUTER_PORT_1_IP);
add_dst_ip_filter_entry(1,$ROUTER_PORT_2_IP);
add_dst_ip_filter_entry(2,$ROUTER_PORT_3_IP);
add_dst_ip_filter_entry(3,$ROUTER_PORT_4_IP);

nf_PCI_write32($delay, $batch, ROUTER_OP_LUT_MULTIPATH_ENABLE_REG (), 1);

#add_LPM_table_entry(0,'171.64.2.0', '255.255.255.0', '171.64.2.1', 0x04);

nf_PCI_write32($delay, $batch, ROUTER_OP_LUT_ROUTE_TABLE_ENTRY_IP_REG(), 0xab400200);
nf_PCI_write32($delay, $batch, ROUTER_OP_LUT_ROUTE_TABLE_ENTRY_MASK_REG(), 0xffffff00);
nf_PCI_write32($delay, $batch, ROUTER_OP_LUT_ROUTE_TABLE_ENTRY_OUTPUT_PORT_REG(), 0x55);
nf_PCI_write32($delay, $batch, ROUTER_OP_LUT_ROUTE_TABLE_ENTRY_NEXT_HOP_IP_REG(), 0x03020100);
nf_PCI_write32($delay, $batch, ROUTER_OP_LUT_GATEWAY_TABLE_ENTRY_IP_REG(), 0xab400101);#171.64.1.1
nf_PCI_write32($delay, $batch, ROUTER_OP_LUT_GATEWAY_TABLE_WR_ADDR_REG(), 0);
nf_PCI_write32($delay, $batch, ROUTER_OP_LUT_GATEWAY_TABLE_ENTRY_IP_REG(), 0xab400201);#171.64.2.1
nf_PCI_write32($delay, $batch, ROUTER_OP_LUT_GATEWAY_TABLE_WR_ADDR_REG(), 1);
nf_PCI_write32($delay, $batch, ROUTER_OP_LUT_GATEWAY_TABLE_ENTRY_IP_REG(), 0xab400301);#171.64.3.1
nf_PCI_write32($delay, $batch, ROUTER_OP_LUT_GATEWAY_TABLE_WR_ADDR_REG(), 2);
nf_PCI_write32($delay, $batch, ROUTER_OP_LUT_GATEWAY_TABLE_ENTRY_IP_REG(), 0xab400401);#171.64.4.1
nf_PCI_write32($delay, $batch, ROUTER_OP_LUT_GATEWAY_TABLE_WR_ADDR_REG(), 3);
nf_PCI_write32($delay, $batch, ROUTER_OP_LUT_ROUTE_TABLE_WR_ADDR_REG(), 0);

# Add the ARP table entries
add_ARP_table_entry(0, '171.64.1.1', $next_hop_1_DA);
add_ARP_table_entry(1, '171.64.2.1', $next_hop_2_DA);
add_ARP_table_entry(2, '171.64.3.1', $next_hop_3_DA);
add_ARP_table_entry(3, '171.64.4.1', $next_hop_4_DA);

my $length = 100;
my $TTL = 30;
my $DA = 0;
my $SA = 0;
my $dst_ip = 0;
my $src_ip = 0;
my $pkt;

#
###############################
#

$delay = '@40us';
$length = 64;
$DA = $ROUTER_PORT_1_MAC;
$SA = '01:55:55:55:55:55';
$dst_ip = '171.64.2.7';
$src_ip = '171.64.8.1';
$pkt = make_IP_pkt($length, $DA, $SA, $TTL, $dst_ip, $src_ip);
nf_packet_in(1, $length, $delay, $batch,  $pkt);
nf_packet_in(1, $length, $delay, $batch,  $pkt);
nf_packet_in(1, $length, $delay, $batch,  $pkt);
nf_packet_in(1, $length, $delay, $batch,  $pkt);
nf_packet_in(1, $length, $delay, $batch,  $pkt);

$DA = $next_hop_1_DA;
$SA = $ROUTER_PORT_1_MAC;
$pkt = make_IP_pkt($length, $DA, $SA, $TTL-1, $dst_ip, $src_ip);
nf_expected_packet(1, $length, $pkt);

$DA = $next_hop_2_DA;
$SA = $ROUTER_PORT_2_MAC;
$pkt = make_IP_pkt($length, $DA, $SA, $TTL-1, $dst_ip, $src_ip);
nf_expected_packet(2, $length, $pkt);

$DA = $next_hop_3_DA;
$SA = $ROUTER_PORT_3_MAC;
$pkt = make_IP_pkt($length, $DA, $SA, $TTL-1, $dst_ip, $src_ip);
nf_expected_packet(3, $length, $pkt);

$DA = $next_hop_4_DA;
$SA = $ROUTER_PORT_4_MAC;
$pkt = make_IP_pkt($length, $DA, $SA, $TTL-1, $dst_ip, $src_ip);
nf_expected_packet(4, $length, $pkt);

$DA = $next_hop_1_DA;
$SA = $ROUTER_PORT_1_MAC;
$pkt = make_IP_pkt($length, $DA, $SA, $TTL-1, $dst_ip, $src_ip);
nf_expected_packet(1, $length, $pkt);


# *********** Finishing Up - need this in all scripts ! ****************************
my $t = nf_write_sim_files();
print  "--- make_pkts.pl: Generated all configuration packets.\n";
printf "--- make_pkts.pl: Last packet enters system at approx %0d microseconds.\n",($t/1000);
if (nf_write_expected_files()) {
  die "Unable to write expected files\n";
}

nf_create_hardware_file('LITTLE_ENDIAN');
nf_write_hardware_file('LITTLE_ENDIAN');
