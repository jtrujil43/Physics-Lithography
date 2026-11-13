package PDL::Demos::Lithography;
use strict;
use warnings;

sub info { ('lithography', 'Laser lithography simulation and plots') }

sub init {
    return q|
use PDL;
use PDL::Graphics::Gnuplot;
use Physics::Lithography::PDLExamples;
|;
}

sub demo {
    return [
        [ comment => q{
            Laser lithography examples using PDL and PDL::Graphics::Gnuplot.
            Each plot can be saved as a PNG with the standalone commands:
              litho-pdl-thermal [output.png]
              litho-pdl-ablation [output.png]
              litho-pdl-scan-dose [output.png]
        } ],
        [ act => q|
Physics::Lithography::PDLExamples::plot_thermal_response();
| ],
        [ act => q|
Physics::Lithography::PDLExamples::plot_ablation_curves();
| ],
        [ act => q|
Physics::Lithography::PDLExamples::plot_scan_dose();
| ],
    ];
}

1;
