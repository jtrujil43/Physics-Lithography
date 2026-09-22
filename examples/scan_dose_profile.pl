#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";

use Physics::Lithography::Pattern;

my $pattern = Physics::Lithography::Pattern->new;

print "Gaussian pulse overlap for a 5 um beam at 100 kHz\n";
printf "%-9s %10s %12s %12s %10s\n",
    'Overlap', 'Pitch um', 'Speed mm/s', 'Mean J/cm2', 'Ripple %';

for my $overlap ( 0, 0.25, 0.50, 0.75 ) {
    my $dose = $pattern->scan_dose_profile(
        fluence    => 0.5,
        spot_size  => 5e-6,
        rep_rate   => 100_000,
        overlap    => $overlap,
        samples    => 201,
        F_threshold => 0.4,
    );

    printf "%8.0f%% %10.3f %12.1f %12.4f %10.3f\n",
        100 * $overlap,
        $dose->{pitch_um},
        $dose->{velocity_mm_s},
        $dose->{mean_fluence},
        100 * $dose->{dose_nonuniformity};
}
