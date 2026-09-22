package Physics::Lithography::Pattern;
use strict;
use warnings;
use Carp;
use List::Util qw(max min);
use Scalar::Util qw(looks_like_number);

# ═══════════════════════════════════════════════════════════════════════════════
# Pattern transfer fidelity model for laser direct imprint
#
# Models:
#   - Feature resolution limits (thermal diffusion length)
#   - Edge acuity and line edge roughness
#   - Aspect ratio achievable
#   - Multi-pulse patterning (scanning)
#   - Overlay and stitching
#   - Process window (fluence vs feature quality)
# ═══════════════════════════════════════════════════════════════════════════════

use constant PI => 3.14159265358979;

sub _is_finite_number {
    my ($value) = @_;
    return 0 unless defined $value && !ref $value && looks_like_number($value);
    my $difference = $value - $value;
    return $difference == $difference;    # false for NaN and infinities
}

sub new {
    my ($class, %opts) = @_;
    my $self = bless {
        verbose => $opts{verbose} // 0,
    }, $class;
    return $self;
}

# Minimum feature size from thermal diffusion
# Resolution ≈ max(optical_spot, 2×L_thermal)
sub minimum_feature_size {
    my ($self, %opts) = @_;
    my $spot   = $opts{spot_size} // 5e-6;       # m
    my $kappa  = $opts{diffusivity} // 1e-7;     # m²/s
    my $tau    = $opts{pulse_width} // 10e-9;    # s

    my $L_th = sqrt($kappa * $tau);              # thermal diffusion length
    my $optical_limit = $spot * 0.5;             # ~half the spot size
    my $thermal_limit = 2 * $L_th;

    return {
        thermal_limit_nm => $thermal_limit * 1e9,
        optical_limit_nm => $optical_limit * 1e9,
        minimum_nm       => max($thermal_limit, $optical_limit) * 1e9,
        L_thermal_nm     => $L_th * 1e9,
    };
}

# Edge acuity: sharpness of feature edge (nm)
# Depends on thermal gradient at ablation boundary
sub edge_acuity {
    my ($self, %opts) = @_;
    my $kappa = $opts{diffusivity} // 1e-7;
    my $tau   = $opts{pulse_width} // 10e-9;
    my $alpha = $opts{alpha} // 1e6;             # 1/m

    # Edge width ≈ thermal diffusion length + optical absorption depth
    my $L_th = sqrt($kappa * $tau);
    my $L_abs = 1.0 / $alpha;

    return {
        edge_width_nm => ($L_th + $L_abs) * 1e9,
        thermal_nm    => $L_th * 1e9,
        optical_nm    => $L_abs * 1e9,
    };
}

# Maximum aspect ratio (depth:width) for ablation
sub max_aspect_ratio {
    my ($self, %opts) = @_;
    my $F      = $opts{fluence} // 0.5;
    my $F_th   = $opts{F_threshold} // 0.1;
    my $alpha  = $opts{alpha} // 1e6;
    my $spot   = $opts{spot_size} // 5e-6;

    return 0 if $F <= $F_th;

    # Depth = (1/α) × ln(F/F_th)
    my $depth = log($F / $F_th) / $alpha;
    # Width ≈ 2 × spot × sqrt(ln(F/F_th)/2) for Gaussian
    my $width = 2 * $spot * sqrt(log($F / $F_th) / 2);

    return ($width > 0) ? $depth / $width : 0;
}

# Process window: map of feature quality vs fluence and spot size
sub process_window {
    my ($self, %opts) = @_;
    my $F_min  = $opts{F_min} // 0.05;
    my $F_max  = $opts{F_max} // 2.0;
    my $alpha  = $opts{alpha} // 1e6;
    my $F_th   = $opts{F_threshold} // 0.1;
    my $spot   = $opts{spot_size} // 5e-6;
    my $kappa  = $opts{diffusivity} // 1e-7;
    my $tau    = $opts{pulse_width} // 10e-9;
    my $n_pts  = $opts{points} // 20;

    my @window;
    for my $i (0 .. $n_pts-1) {
        my $F = $F_min * exp(log($F_max/$F_min) * $i / ($n_pts-1));
        my $depth = ($F > $F_th) ? log($F / $F_th) / $alpha * 1e9 : 0;
        my $width = ($F > $F_th)
            ? 2 * $spot * sqrt(log($F / $F_th) / 2) * 1e9 : 0;
        my $L_th = sqrt($kappa * $tau) * 1e9;
        my $quality = ($depth > 0 && $width > 0)
            ? min(1.0, $depth / max($L_th, 1)) * min(1.0, 100 / max($width - $spot*1e9, 1))
            : 0;

        push @window, {
            fluence    => $F,
            depth_nm   => $depth,
            width_nm   => $width,
            quality    => $quality,  # 0-1 figure of merit
        };
    }
    return \@window;
}

# Scanning pattern: pitch and overlap for continuous features
sub scan_parameters {
    my ($self, %opts) = @_;
    my $spot    = $opts{spot_size} // 5e-6;      # m
    my $overlap = $opts{overlap} // 0.5;         # 50% overlap
    my $rep_rate = $opts{rep_rate} // 1000;      # Hz
    my $velocity = $opts{velocity} // undef;     # m/s (auto if undef)

    my $pitch = $spot * (1 - $overlap) * 2;      # distance between pulses
    $velocity //= $pitch * $rep_rate;

    return {
        pitch_um    => $pitch * 1e6,
        velocity_mm_s => $velocity * 1e3,
        throughput_cm2_s => $velocity * $spot * 2 * 1e4,
        dwell_time_ns => 1.0 / $rep_rate * 1e9,
    };
}

# Accumulated Gaussian dose over one pulse-to-pulse period of a scanned line.
# The finite sum is automatically extended until omitted pulse tails are tiny.
sub scan_dose_profile {
    my ($self, %opts) = @_;

    my $fluence = $opts{fluence} // 0.5;          # J/cm^2 per pulse at center
    my $spot    = $opts{spot_size} // 5e-6;       # m, 1/e^2 radius
    my $rep     = $opts{rep_rate} // 1000;        # Hz
    my $samples = $opts{samples} // 101;

    croak 'scan_dose_profile(): fluence must be non-negative and finite'
        unless _is_finite_number($fluence) && $fluence >= 0;
    croak 'scan_dose_profile(): spot_size must be positive and finite'
        unless _is_finite_number($spot) && $spot > 0;
    croak 'scan_dose_profile(): rep_rate must be positive and finite'
        unless _is_finite_number($rep) && $rep > 0;
    croak 'scan_dose_profile(): samples must be an integer from 2 to 10001'
        unless $samples =~ /\A\d+\z/ && $samples >= 2 && $samples <= 10001;

    my ( $pitch, $velocity, $overlap );
    if ( defined $opts{velocity} ) {
        croak 'scan_dose_profile(): specify either overlap or velocity, not both'
            if defined $opts{overlap};
        $velocity = $opts{velocity};
        croak 'scan_dose_profile(): velocity must be positive and finite'
            unless _is_finite_number($velocity) && $velocity > 0;
        $pitch   = $velocity / $rep;
        $overlap = 1 - $pitch / ( 2 * $spot );
    }
    else {
        $overlap = $opts{overlap} // 0.5;
        croak 'scan_dose_profile(): overlap must be at least 0 and less than 1'
            unless _is_finite_number($overlap)
                && $overlap >= 0 && $overlap < 1;
        $pitch    = 2 * $spot * ( 1 - $overlap );
        $velocity = $pitch * $rep;
    }

    my $span = $opts{pulses_each_side};
    if ( defined $span ) {
        croak 'scan_dose_profile(): pulses_each_side must be an integer from 0 to 10000'
            unless $span =~ /\A\d+\z/ && $span <= 10000;
    }
    else {
        # Include pulses until a Gaussian centered beyond the sampled period
        # contributes less than roughly 1e-12 of its peak.
        my $needed = $spot / $pitch * sqrt( log(1e12) / 2 ) + 0.5;
        $span = int($needed);
        ++$span if $span < $needed;
        croak 'scan_dose_profile(): overlap is too close to 1 for automatic summation'
            if $span > 10000;
    }

    my @profile;
    my ( $min_dose, $max_dose );
    my $weighted_sum   = 0;
    my $weighted_above = 0;
    my $threshold = $opts{F_threshold};
    croak 'scan_dose_profile(): F_threshold must be non-negative and finite'
        if defined $threshold
            && ( !_is_finite_number($threshold) || $threshold < 0 );

    for my $i ( 0 .. $samples - 1 ) {
        my $x = -$pitch / 2 + $pitch * $i / ( $samples - 1 );
        my $dose = 0;
        for my $pulse ( -$span .. $span ) {
            my $dx = $x - $pulse * $pitch;
            $dose += $fluence * exp( -2 * $dx * $dx / ( $spot * $spot ) );
        }

        push @profile, { x_um => $x * 1e6, fluence => $dose };
        $min_dose = $dose if !defined $min_dose || $dose < $min_dose;
        $max_dose = $dose if !defined $max_dose || $dose > $max_dose;
        my $weight = ( $i == 0 || $i == $samples - 1 ) ? 0.5 : 1;
        $weighted_sum += $weight * $dose;
        $weighted_above += $weight
            if defined $threshold && $dose >= $threshold;
    }

    my $mean = $weighted_sum / ( $samples - 1 );
    my $denominator = $max_dose + $min_dose;
    my $nonuniformity = $denominator > 0
        ? ( $max_dose - $min_dose ) / $denominator : 0;

    my %result = (
        pitch_um           => $pitch * 1e6,
        velocity_mm_s      => $velocity * 1e3,
        overlap            => $overlap,
        min_fluence        => $min_dose,
        max_fluence        => $max_dose,
        mean_fluence       => $mean,
        dose_nonuniformity => $nonuniformity,
        pulses_summed      => 2 * $span + 1,
        profile            => \@profile,
    );
    $result{fraction_above_threshold} = $weighted_above / ( $samples - 1 )
        if defined $threshold;

    return \%result;
}

# Line pattern: predict line width and depth for scanning
sub line_pattern {
    my ($self, %opts) = @_;
    my $F      = $opts{fluence} // 0.5;
    my $spot   = $opts{spot_size} // 5e-6;
    my $F_th   = $opts{F_threshold} // 0.1;
    my $alpha  = $opts{alpha} // 1e6;
    my $overlap = $opts{overlap} // 0.5;
    my $N_eff  = 1.0 / (1.0 - $overlap);  # effective pulse overlap count

    return { width_nm => 0, depth_nm => 0 } if $F <= $F_th;

    # Width of ablated region
    my $r_abl = $spot * sqrt(log($F / $F_th) / 2);
    my $width = 2 * $r_abl;

    # Depth enhanced by overlap (accumulation)
    my $depth = log($F * $N_eff / $F_th) / $alpha;
    $depth = max($depth, 0);

    return {
        width_nm => $width * 1e9,
        depth_nm => $depth * 1e9,
        aspect_ratio => ($width > 0) ? $depth / $width : 0,
    };
}

# Resolution comparison for different wavelengths/pulsewidths
sub resolution_comparison {
    my ($self, %opts) = @_;
    my @configs = @{$opts{configs} // [
        { name => '355nm/10ns',  wavelength => 355e-9, pulse_width => 10e-9 },
        { name => '248nm/25ns',  wavelength => 248e-9, pulse_width => 25e-9 },
        { name => '355nm/100ps', wavelength => 355e-9, pulse_width => 100e-12 },
        { name => '800nm/100fs', wavelength => 800e-9, pulse_width => 100e-15 },
    ]};
    my $kappa = $opts{diffusivity} // 1e-7;

    my @results;
    for my $cfg (@configs) {
        my $L_th = sqrt($kappa * $cfg->{pulse_width});
        push @results, {
            name => $cfg->{name},
            L_thermal_nm => $L_th * 1e9,
            resolution_nm => 2 * $L_th * 1e9,
        };
    }
    return \@results;
}

1;

__END__

=head1 NAME

Physics::Lithography::Pattern - laser pattern-transfer and scan-dose models

=head1 SCANNED-LINE DOSE

C<scan_dose_profile(%options)> sums neighboring Gaussian pulses over one
pulse-pitch period.  Supply C<fluence>, C<spot_size>, C<rep_rate>, and either
C<overlap> or C<velocity>.  It returns the derived pitch and velocity, sampled
dose profile, minimum/maximum/mean fluence, and the standard half-range dose
nonuniformity C<(max-min)/(max+min)>.  If C<F_threshold> is supplied, the
result also includes C<fraction_above_threshold>.

The optional C<pulses_each_side> controls the finite pulse train explicitly;
otherwise enough neighbors are included to reduce Gaussian-tail truncation.
Numeric physical inputs must be finite.  C<overlap> and C<velocity> are
mutually exclusive.  Threshold coverage is integrated over the sampled period,
with the duplicate periodic endpoints receiving half weight.

=cut
