#!/usr/bin/env perl
use strict;
use warnings;
use v5.10;

use File::Basename;

sub usage {
    say STDERR<<"EOF";

usage: $0 <training_start> <training_end> <test_start> <test_end>
Date format: 2019-03-19T23:59:59

Generates experiment.env files for each active campaign (retargeting)

EOF
    exit 1;
}

# Find profileview et al in case we aren't in /srv/profileview
sub find_base() {
        my($base);

        $base = dirname($0);

        if (-x $base . '/profileview') {
                return $base;
        }

        if (-x '/srv/profileview/profileview') {
                return '/srv/profileview';      
        }

        say STDERR "can't find profileview";
        exit 1;
}

if (@ARGV != 4) {
    usage();
}

# Settings common to all campaigns
my ($training_start, $training_end, $test_start, $test_end) = @ARGV;
my $region = `hostname` =~ s/-\d+\n//r;

# Find directory profileview is in
my $base = find_base();

# Create mapping of adpan IDs to adpan names
my %adpan_names;
{
    open my $f_adpan, '-|', "$base/profileview -c adpan_metadata -A"
        or die "Unable to run profileview: $!\n";
    my $adpan_id;
    while (<$f_adpan>) {
        if (/^   Hash id : (.*)$/) {
            $adpan_id = $1;
        } elsif (/^   char\[\] adpan_name \(length \d++\): (.*)$/) {
            $adpan_names{$adpan_id} = $1;
        } elsif (/^$/) {
            undef $adpan_id;
        }
    }
}

# Loop through all campaigns and generate output files.
# Output file naming schema: "experiment_<adpan_name>_<campaign_id>.env"
open my $f_campaign, '-|', "$base/profileview -c campaign_metadata -A"
    or die "Unable to run profileview: $!\n";

my ($adpan_id, $adpan_name, $campaign_id);
while (<$f_campaign>) {
    if (/^   ulong id : (\d+)\s*$/) {
        $campaign_id = $1;
    } elsif (/^   Hash adpan_id : (\d+) *$/) {
        $adpan_id = $1;
    } elsif (/^$/) {
        open my $f_out, '>', "experiment_$adpan_names{$adpan_id}_$campaign_id.env";
        print $f_out <<"EOF";
ADPAN_ID=$adpan_id
ADPAN_NAME=$adpan_names{$adpan_id}
CAMPAIGN_ID=$campaign_id
REGION=$region
RANKING_PATH="data/ranking.txt" #(by default)
PROCESSING_MODE="complete" #("basket and sales", "user sessions", "complete"
TRAINING_START=$training_start
TRAINING_END=$training_end
TEST_START=$test_start
TEST_END=$test_end
EOF
        close $f_out;
    }
}