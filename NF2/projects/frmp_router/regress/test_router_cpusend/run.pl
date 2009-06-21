#!/usr/bin/perl -w

use strict;
use NF2::RegressLib;
use NF2::PacketLib;
use RegressRouterLib;

use reg_defines_cs344_starter;

use constant NUM_PKTS => 20;

my @interfaces = ("nf2c0", "nf2c1", "nf2c2", "nf2c3", "eth1", "eth2");
nftest_init(\@ARGV,\@interfaces,);
nftest_start(\@interfaces,);

nftest_fpga_reset('nf2c0');

my $routerMAC0 = "00:ca:fe:00:00:01";
my $routerMAC1 = "00:ca:fe:00:00:02";
my $routerMAC2 = "00:ca:fe:00:00:03";
my $routerMAC3 = "00:ca:fe:00:00:04";

my $routerIP0 = "192.168.0.40";
my $routerIP1 = "192.168.1.40";
my $routerIP2 = "192.168.2.40";
my $routerIP3 = "192.168.3.40";

my $ALLSPFRouters = "224.0.0.5";


######### You should skip this section for tests with router SCONE
# Write the mac and IP addresses doesn't matter which of the nf2c0..3 you write to.
nftest_add_dst_ip_filter_entry ('nf2c0', 0, $routerIP0);
nftest_add_dst_ip_filter_entry ('nf2c0', 1, $routerIP1);
nftest_add_dst_ip_filter_entry ('nf2c0', 2, $routerIP2);
nftest_add_dst_ip_filter_entry ('nf2c0', 3, $routerIP3);
nftest_add_dst_ip_filter_entry ('nf2c0', 4, $ALLSPFRouters);

# For these it does matter which interface you write to
nftest_set_router_MAC ('nf2c0', $routerMAC0);
nftest_set_router_MAC ('nf2c1', $routerMAC1);
nftest_set_router_MAC ('nf2c2', $routerMAC2);
nftest_set_router_MAC ('nf2c3', $routerMAC3);
#########

# Put the two ports in loopback mode. Pkts going out will come back in on
# the same port
nftest_phy_loopback('nf2c2');
nftest_phy_loopback('nf2c3');

nftest_regread_expect('nf2c0', MDIO_PHY_0_CONTROL_REG(), 0x1140);
nftest_regread_expect('nf2c0', MDIO_PHY_1_CONTROL_REG(), 0x1140);
nftest_regread_expect('nf2c0', MDIO_PHY_2_CONTROL_REG(), 0x5140);
nftest_regread_expect('nf2c0', MDIO_PHY_3_CONTROL_REG(), 0x5140);

# set parameters
my $DA = $routerMAC0;
my $SA = "aa:bb:cc:dd:ee:ff";
my $TTL = 64;
my $DST_IP = "192.168.1.1";
my $SRC_IP = "192.168.0.1";;
my $nextHopMAC = "dd:55:dd:66:dd:77";

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

my $num_precreated = 1000;
my $start_val = $MAC_hdr->length_in_bytes() + $IP_hdr->length_in_bytes()+1;

# precreate random sized packets
$MAC_hdr->DA($routerMAC0);
my @precreated0 = nftest_precreate_pkts($num_precreated,
                                        $MAC_hdr->packed . $IP_hdr->packed);
$MAC_hdr->DA($routerMAC1);
my @precreated1 = nftest_precreate_pkts($num_precreated,
                                        $MAC_hdr->packed . $IP_hdr->packed);
$MAC_hdr->DA($routerMAC2);
my @precreated2 = nftest_precreate_pkts($num_precreated,
                                        $MAC_hdr->packed . $IP_hdr->packed);
$MAC_hdr->DA($routerMAC3);
my @precreated3 = nftest_precreate_pkts($num_precreated,
                                        $MAC_hdr->packed . $IP_hdr->packed);

# reset counters
nftest_regwrite("nf2c0", MAC_GRP_0_RX_QUEUE_NUM_PKTS_STORED_REG(), 0);
nftest_regwrite("nf2c0", MAC_GRP_0_TX_QUEUE_NUM_PKTS_SENT_REG(), 0);
nftest_regwrite("nf2c0", MAC_GRP_0_RX_QUEUE_NUM_BYTES_PUSHED_REG(), 0);
nftest_regwrite("nf2c0", MAC_GRP_0_TX_QUEUE_NUM_BYTES_PUSHED_REG(), 0);

nftest_regwrite("nf2c0", MAC_GRP_1_RX_QUEUE_NUM_PKTS_STORED_REG(), 0);
nftest_regwrite("nf2c0", MAC_GRP_1_TX_QUEUE_NUM_PKTS_SENT_REG(), 0);
nftest_regwrite("nf2c0", MAC_GRP_1_RX_QUEUE_NUM_BYTES_PUSHED_REG(), 0);
nftest_regwrite("nf2c0", MAC_GRP_1_TX_QUEUE_NUM_BYTES_PUSHED_REG(), 0);

nftest_regwrite("nf2c0", MAC_GRP_2_RX_QUEUE_NUM_PKTS_STORED_REG(), 0);
nftest_regwrite("nf2c0", MAC_GRP_2_TX_QUEUE_NUM_PKTS_SENT_REG(), 0);
nftest_regwrite("nf2c0", MAC_GRP_2_RX_QUEUE_NUM_BYTES_PUSHED_REG(), 0);
nftest_regwrite("nf2c0", MAC_GRP_2_TX_QUEUE_NUM_BYTES_PUSHED_REG(), 0);

nftest_regwrite("nf2c0", MAC_GRP_3_RX_QUEUE_NUM_PKTS_STORED_REG(), 0);
nftest_regwrite("nf2c0", MAC_GRP_3_TX_QUEUE_NUM_PKTS_SENT_REG(), 0);
nftest_regwrite("nf2c0", MAC_GRP_3_RX_QUEUE_NUM_BYTES_PUSHED_REG(), 0);
nftest_regwrite("nf2c0", MAC_GRP_3_TX_QUEUE_NUM_BYTES_PUSHED_REG(), 0);

nftest_regwrite("nf2c0", ROUTER_OP_LUT_NUM_CPU_PKTS_SENT_REG(), 0);

print "Sending now: \n";
my $pkt;
my @totalPktLengths = (0, 0, 0, 0);
# send 10000 packets from ports nf2c0...nf2c3
for(my $i=0; $i<NUM_PKTS; $i++){
  print "$i \r";
  $pkt = $precreated0[int(rand($num_precreated))];
  $totalPktLengths[0] += length($pkt);
  nftest_send('nf2c0', $pkt);
  nftest_expect('eth1', $pkt);
	`usleep 100`;
  $pkt = $precreated1[int(rand($num_precreated))];
  $totalPktLengths[1] += length($pkt);
  nftest_send('nf2c1', $pkt);
  nftest_expect('eth2', $pkt);
	`usleep 100`;
  # packets are looped back and will be sent to the CPU due to an LPM miss
  $pkt = $precreated2[int(rand($num_precreated))];
  $totalPktLengths[2] += length($pkt);
  nftest_send('nf2c2', $pkt);
  nftest_expect('nf2c2', $pkt);

  $pkt = $precreated3[int(rand($num_precreated))];
  $totalPktLengths[3] += length($pkt);
  nftest_send('nf2c3', $pkt);
  nftest_expect('nf2c3', $pkt);
	`usleep 1000`;
}

print "\n";

sleep 2;

my $unmatched_hoh = nftest_finish();
nftest_reset_phy();

my $total_errors = 0;

print "Checking pkt errors\n";
$total_errors += nftest_print_errors($unmatched_hoh);

# check counter values
nftest_regread_expect("nf2c0", MAC_GRP_0_TX_QUEUE_NUM_PKTS_SENT_REG(), NUM_PKTS);
nftest_regread_expect("nf2c0", MAC_GRP_0_TX_QUEUE_NUM_BYTES_PUSHED_REG(), $totalPktLengths[0]);

nftest_regread_expect("nf2c0", MAC_GRP_1_TX_QUEUE_NUM_PKTS_SENT_REG(), NUM_PKTS);
nftest_regread_expect("nf2c0", MAC_GRP_1_TX_QUEUE_NUM_BYTES_PUSHED_REG(), $totalPktLengths[1]);

nftest_regread_expect("nf2c0", MAC_GRP_2_RX_QUEUE_NUM_PKTS_STORED_REG(), NUM_PKTS);
nftest_regread_expect("nf2c0", MAC_GRP_2_TX_QUEUE_NUM_PKTS_SENT_REG(), NUM_PKTS);
nftest_regread_expect("nf2c0", MAC_GRP_2_RX_QUEUE_NUM_BYTES_PUSHED_REG(), $totalPktLengths[2]);
nftest_regread_expect("nf2c0", MAC_GRP_2_TX_QUEUE_NUM_BYTES_PUSHED_REG(), $totalPktLengths[2]);

nftest_regread_expect("nf2c0", MAC_GRP_3_RX_QUEUE_NUM_PKTS_STORED_REG(), NUM_PKTS);
nftest_regread_expect("nf2c0", MAC_GRP_3_TX_QUEUE_NUM_PKTS_SENT_REG(), NUM_PKTS);
nftest_regread_expect("nf2c0", MAC_GRP_3_RX_QUEUE_NUM_BYTES_PUSHED_REG(), $totalPktLengths[3]);
nftest_regread_expect("nf2c0", MAC_GRP_3_TX_QUEUE_NUM_BYTES_PUSHED_REG(), $totalPktLengths[3]);

nftest_regread_expect("nf2c0", ROUTER_OP_LUT_NUM_CPU_PKTS_SENT_REG(), 4*NUM_PKTS);

my $check_value = nftest_regread("nf2c0", ROUTER_OP_LUT_NUM_PKTS_FORWARDED_REG());
print"$check_value\n";

my $check_value = nftest_regread("nf2c0", ROUTER_OP_LUT_NUM_PKTS_FORWARDED_REG());
print"$check_value\n";


if ($total_errors==0) {
  print "Test PASSES\n";
  exit 0;
}
else {
  print "Test FAILED: $total_errors errors\n";
  exit 1;
}
