use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use Physics::Lithography::Pattern;

sub close_to {
    my ( $got, $want, $tolerance, $message ) = @_;
    ok( abs( $got - $want ) <= $tolerance, $message )
        or diag "got $got, expected $want +/- $tolerance";
}

my $pattern = Physics::Lithography::Pattern->new;

# Existing scan-parameter behavior is retained.
my $scan = $pattern->scan_parameters(
    spot_size => 5e-6, overlap => 0.5, rep_rate => 100_000,
);
close_to( $scan->{pitch_um}, 5, 1e-12, 'legacy scan pitch remains unchanged' );
close_to( $scan->{velocity_mm_s}, 500, 1e-9,
    'legacy automatic velocity remains unchanged' );

my $dose = $pattern->scan_dose_profile(
    fluence    => 0.5,
    spot_size  => 5e-6,
    overlap    => 0.5,
    rep_rate   => 100_000,
    samples    => 101,
    F_threshold => 0.625,
);

is( scalar @{ $dose->{profile} }, 101, 'dose profile contains requested samples' );
close_to( $dose->{pitch_um}, 5, 1e-12, 'dose model derives pulse pitch' );
close_to( $dose->{velocity_mm_s}, 500, 1e-9, 'dose model derives scan velocity' );
close_to( $dose->{mean_fluence}, 0.5 * sqrt( 3.14159265358979 / 2 ),
    1e-8, 'mean dose agrees with integral of periodic Gaussian train' );
ok( $dose->{max_fluence} > $dose->{min_fluence},
    'finite pitch produces measurable dose ripple' );
ok( $dose->{dose_nonuniformity} < 0.02,
    '50 percent overlap gives a nearly uniform centerline dose' );
ok( $dose->{fraction_above_threshold} > 0
        && $dose->{fraction_above_threshold} < 1,
    'threshold coverage fraction is reported' );
my $weighted_above = 0;
for my $i ( 0 .. $#{ $dose->{profile} } ) {
    my $weight = ( $i == 0 || $i == $#{ $dose->{profile} } ) ? 0.5 : 1;
    $weighted_above += $weight
        if $dose->{profile}[$i]{fluence} >= 0.625;
}
close_to( $dose->{fraction_above_threshold}, $weighted_above / 100, 1e-12,
    'threshold coverage does not double-count the periodic endpoint' );

my $below_threshold = $pattern->scan_dose_profile(
    fluence => 0, F_threshold => 0.1,
);
is( $below_threshold->{fraction_above_threshold}, 0,
    'threshold coverage is zero when no sample reaches the threshold' );

my $separated = $pattern->scan_dose_profile(
    fluence => 0.5, spot_size => 5e-6, overlap => 0, samples => 101,
);
my $dense = $pattern->scan_dose_profile(
    fluence => 0.5, spot_size => 5e-6, overlap => 0.75, samples => 101,
);
ok( $dense->{dose_nonuniformity} < $separated->{dose_nonuniformity},
    'more pulse overlap reduces periodic dose ripple' );
ok( $dense->{mean_fluence} > $separated->{mean_fluence},
    'more pulse overlap raises accumulated mean dose' );

my $velocity_driven = $pattern->scan_dose_profile(
    spot_size => 5e-6, rep_rate => 100_000, velocity => 1,
);
close_to( $velocity_driven->{pitch_um}, 10, 1e-12,
    'explicit velocity determines pitch' );
close_to( $velocity_driven->{overlap}, 0, 1e-12,
    'derived overlap is returned for velocity-driven scans' );

my @bad = (
    [ { overlap => 1 }, qr/overlap must be at least 0 and less than 1/,
        'complete overlap is rejected' ],
    [ { velocity => 0 }, qr/velocity must be positive/,
        'zero scan velocity is rejected' ],
    [ { samples => 1 }, qr/samples must be an integer from 2 to 10001/,
        'too few samples are rejected' ],
    [ { fluence => -0.1 }, qr/fluence must be non-negative/,
        'negative fluence is rejected' ],
    [ { fluence => 'not-a-number' }, qr/fluence must be non-negative/,
        'nonnumeric fluence is rejected' ],
    [ { F_threshold => 'Inf' }, qr/F_threshold must be non-negative/,
        'non-finite threshold is rejected' ],
    [ { velocity => 1, overlap => 0.5 }, qr/either overlap or velocity/,
        'conflicting pitch controls are rejected' ],
);

for my $case (@bad) {
    my ( $args, $regex, $message ) = @$case;
    eval { $pattern->scan_dose_profile(%$args) };
    like( $@, $regex, $message );
}

done_testing;
