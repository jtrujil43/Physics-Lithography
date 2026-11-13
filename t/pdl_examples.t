use strict;
use warnings;
use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib "$FindBin::Bin/../lib";

eval { require Physics::Lithography::PDLExamples; 1 } or plan skip_all =>
    'PDL and PDL::Graphics::Gnuplot are optional dependencies';
plan skip_all => 'gnuplot executable is required to render the examples'
    unless grep { -x File::Spec->catfile($_, 'gnuplot') } File::Spec->path;

require PDL::Demos;
my @demo_info = PDL::Demos->info('lithography');
is($demo_info[0], 'lithography', 'PDL demo is discoverable');
is(scalar @{PDL::Demos->demo('lithography')}, 4,
    'PDL demo contains the introduction and three plots');

my $dir = tempdir(CLEANUP => 1);
my @examples = (
    [ \&Physics::Lithography::PDLExamples::plot_thermal_response, 'thermal.png' ],
    [ \&Physics::Lithography::PDLExamples::plot_ablation_curves,  'ablation.png' ],
    [ \&Physics::Lithography::PDLExamples::plot_scan_dose,        'scan-dose.png' ],
);

for my $example (@examples) {
    my ($plot, $name) = @$example;
    my $path = "$dir/$name";
    $plot->($path);
    ok(-s $path, "$name plot writes a non-empty PNG");
    open my $fh, '<:raw', $path or die "Cannot read $path: $!";
    read $fh, my $signature, 8;
    close $fh or die "Cannot close $path: $!";
    is($signature, "\x89PNG\r\n\x1a\n", "$name output is a PNG image");
}

done_testing;
