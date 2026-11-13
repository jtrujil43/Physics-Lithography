use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'Physics::Lithography',
    VERSION_FROM => 'lib/Physics/Lithography.pm',
    ABSTRACT     => 'Laser Direct Imprint Lithography simulation toolkit',
    AUTHOR       => 'Jovan Trujillo',
    LICENSE      => 'perl',
    PREREQ_PM    => {
        'Carp'       => 0,
        'List::Util' => 0,
        'Scalar::Util' => 0,
        'File::Path' => 0,
    },
    META_MERGE => {
        'meta-spec' => { version => 2 },
        prereqs => {
            runtime => {
                recommends => {
                    'PDL'                    => 0,
                    'PDL::Graphics::Gnuplot' => 0,
                },
            },
        },
        resources => {
            repository => 'https://github.com/jtrujil43/Physics-Lithography',
        },
    },
    EXE_FILES => [
        'examples/litho-pdl-thermal',
        'examples/litho-pdl-ablation',
        'examples/litho-pdl-scan-dose',
    ],
);
