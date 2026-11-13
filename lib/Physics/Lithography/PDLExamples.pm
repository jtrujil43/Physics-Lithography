package Physics::Lithography::PDLExamples;
use strict;
use warnings;

use PDL;
use PDL::Graphics::Gnuplot;
use Physics::Lithography::Ablation;
use Physics::Lithography::Laser;
use Physics::Lithography::Pattern;
use Physics::Lithography::Thermal;

sub plot_thermal_response {
    my ($output) = @_;

    my $laser = Physics::Lithography::Laser->new(
        wavelength  => 355e-9,
        pulse_width => 10e-9,
        fluence     => 0.5,
        spot_size   => 5e-6,
    );
    my $thermal = Physics::Lithography::Thermal->new(
        material => 'pmma',
        nr       => 41,
        nz       => 31,
        r_max    => 20e-6,
        z_max    => 5e-6,
    );
    $thermal->solve(laser => $laser, time => 100e-9, steps => 300);

    my $dr = $thermal->grid_info->{dr};
    my $surface_values = $thermal->surface_temperature;
    my $radius = pdl([map { $_ * $dr * 1e6 } 0 .. $#$surface_values]);
    my $surface = pdl($surface_values);
    my %options = (
        title  => 'PMMA surface temperature after a 355 nm pulse',
        xlabel => 'Radius (um)',
        ylabel => 'Temperature (K)',
    );
    $options{hardcopy} = $output if defined $output;
    gplot(\%options, $radius, $surface);

    return $output;
}

sub plot_ablation_curves {
    my ($output) = @_;

    my $ablation = Physics::Lithography::Ablation->new(
        alpha       => 1e5,
        F_threshold => 0.1,
        incubation_S => 0.85,
    );
    my @fluence = map { 0.05 + $_ * (2.0 - 0.05) / 99 } 0 .. 99;
    my $x = pdl(\@fluence);
    my %options = (
        title  => 'Ablation depth with pulse incubation',
        xlabel => 'Fluence per pulse (J/cm^2)',
        ylabel => 'Accumulated depth (nm)',
    );
    $options{hardcopy} = $output if defined $output;

    my @plot = (\%options);
    for my $pulses (1, 10, 100) {
        my $threshold = $ablation->threshold_with_incubation(N => $pulses);
        my @depth = map {
            $pulses * $ablation->ablation_depth(
                fluence          => $_,
                F_threshold_eff  => $threshold,
            ) * 1e9
        } @fluence;
        push @plot, { with => 'lines', legend => "$pulses pulses" },
            $x, pdl(\@depth);
    }
    gplot(@plot);

    return $output;
}

sub plot_scan_dose {
    my ($output) = @_;

    my $pattern = Physics::Lithography::Pattern->new;
    my %options = (
        title  => 'Accumulated Gaussian dose over a scanned line',
        xlabel => 'Position within pulse pitch (um)',
        ylabel => 'Accumulated fluence (J/cm^2)',
    );
    $options{hardcopy} = $output if defined $output;

    my @plot = (\%options);
    for my $overlap (0, 0.5, 0.75) {
        my $dose = $pattern->scan_dose_profile(
            fluence   => 0.5,
            spot_size => 5e-6,
            rep_rate  => 100_000,
            overlap   => $overlap,
            samples   => 201,
        );
        my $x = pdl([map { $_->{x_um} } @{$dose->{profile}}]);
        my $y = pdl([map { $_->{fluence} } @{$dose->{profile}}]);
        push @plot, { with => 'lines', legend => sprintf('%d%% overlap', 100 * $overlap) },
            $x, $y;
    }
    gplot(@plot);

    return $output;
}

1;
