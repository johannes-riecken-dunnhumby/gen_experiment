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
my $criteria_fulfilled = 0;

while (processNextCampaign()) {
    if ($criteria_fulfilled == 5) {
        open my $f_out, '>', "experiment_$adpan_names{$adpan_id}_$campaign_id.env";
        print $f_out <<"EOF";
ADPApan_id
ADPA$adpan_names{$adpan_id}"
CAMP$campaign_id
REGIion"
RANK="data/$opts{tag}_$adpan_names{$adpan_id}_ranking.txt"
PROCODE="$opts{processing_mode}"
TRAIRT=$opts{training_start}
TRAI=$opts{training_end}
TESTopts{test_start}
TESTts{test_end}
EOF
        close $f_out;
    }

}

sub processNextCampaign {
    # criteria:
    # - contains DynamicAdGroup
    # - status is active for at least 1 dynamicadgroup
    # - status is active for campaign
    # - start time < now, end time > now or 0
    my $found_active_dynamic;
    my $now = time();

    while (!eof && ($_ = <$f_campaign>) !~ /^$/) {
        if (/^   ulong id : (\d+)\s*$/) {
            $campaign_id = $1;
        } elsif (/^   Hash adpan_id : (\d+) *$/) {
            $adpan_id = $1;
        } elsif ($_ eq "      struct DynamicAdGroup:\n") {
            $criteria_fulfilled++;
        } elsif ($criteria_fulfilled >= 1 .. /^         /) {
          # if found Dynamic and while indent level is higher
            if ($_ eq "         ubyte status : 1\n" && !$found_active_dynamic) {
                $criteria_fulfilled++;
                $found_active_dynamic = 1;
            }
        } elsif ($_ eq "   ubyte status : 1\n") { # campaign status
            $criteria_fulfilled++;
        } elsif ($_ eq "         struct valid_utc:\n") {
            $_ = <$f_campaign>;
            my ($min) = /^ {12}TimeStamp min : (\d+)$/;
            if ($min < $now) {
                $criteria_fulfilled++;
            }
            $_ = <$f_campaign>;
            my ($max) = /^ {12}TimeStamp max : (\d+)$/;
            if ($max > $now || $max == 0) {
                $criteria_fulfilled++;
            }
        }
    }
    return !eof;
}
