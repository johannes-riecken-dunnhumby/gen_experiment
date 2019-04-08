#!/usr/bin/env perl
use strict;
use warnings;
use v5.10;

use File::Basename;

my %opts;
my @opt_names = qw(tag processing_mode training_start training_end test_start test_end);
my $usage_opts = join ' ', map { "<$_>" } @opt_names;
sub usage {
    say STDERR<<"EOF";

usage: $0 $usage_opts
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

if (@ARGV != @opt_names) {
    usage();
}

# Settings common to all campaigns
@opts{@opt_names} = @ARGV;
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
# criteria: contains DynamicAdGroup and status is active
my $criteria_fulfilled = 0;
while (<$f_campaign>) {
    if (/^   ulong id : (\d+)\s*$/) {
        $campaign_id = $1;
    } elsif (/^   Hash adpan_id : (\d+) *$/) {
        $adpan_id = $1;
    } elsif ($_ eq "      struct DynamicAdGroup:\n") {
        $criteria_fulfilled = 1;
    } elsif ($criteria_fulfilled == 1 .. /^         /) {
      # if found Dynamic and while indent level is higher
        $criteria_fulfilled = 2 if $_ eq "         ubyte status : 1\n";
    } elsif (/^$/) {
        if ($criteria_fulfilled == 2) {
            open my $f_out, '>', "experiment_$adpan_names{$adpan_id}_$campaign_id.env";
            print $f_out <<"EOF";
ADPAN_ID=$adpan_id
ADPAN_NAME="$adpan_names{$adpan_id}"
CAMPAIGN_ID=$campaign_id
REGION="$region"
RANKING_PATH="data/$opts{tag}_$adpan_names{$adpan_id}_ranking.txt"
PROCESSING_MODE="$opts{processing_mode}"
TRAINING_START=$opts{training_start}
TRAINING_END=$opts{training_end}
TEST_START=$opts{test_start}
TEST_END=$opts{test_end}
EOF
            close $f_out;
        }
        $criteria_fulfilled = 0;
    }
}
