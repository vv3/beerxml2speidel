#! /usr/bin/perl
# 
# Read BeerXML from file or stdin, convert to Speidel recipe
# Optionally upload recipe to Speidel
# Inspired from
# https://forum.braumeisters.net/viewtopic.php?f=11&t=1418&start=30

use strict;
use Getopt::Long;
use XML::LibXML::Simple ();
use Data::Dumper;
use Getopt::Long;
use LWP::UserAgent;
use URI::Escape;

my $debug     = 0;
my $recipe_no = 9; # Recipe index
my $speidel;    # IP/hostname of speidel

GetOptions
    (
     'debug'       => \$debug,
     'recipe_no:i' => \$recipe_no,
     'speidel:s'   => \$speidel,
    );

my $file = shift || '-';

my %options;
my $xs   = XML::LibXML::Simple->new(%options);

my $data = $xs->XMLin($file, %options);

print STDERR "Parsed XML:", Dumper $data if $debug;
my $recipe = $data->{RECIPE};
my $recipe_name = $recipe->{NAME};
my $mashin_temp;
my @mash_steps = ([0,0],[0,0],[0,0],[0,0],[0,0]); # Initialize mash steps
my @recipe_mash_steps;
if (ref $recipe->{MASH}->{MASH_STEPS}->{MASH_STEP} eq 'ARRAY') {
    @recipe_mash_steps = @{$recipe->{MASH}->{MASH_STEPS}->{MASH_STEP}};
    $mashin_temp = $recipe->{MASH}->{MASH_STEPS}->{MASH_STEP}->[0]->{STEP_TEMP};
} elsif ($recipe->{MASH}->{MASH_STEPS}->{MASH_STEP}) {
    @recipe_mash_steps = $recipe->{MASH}->{MASH_STEPS}->{MASH_STEP};
    $mashin_temp = $recipe->{MASH}->{MASH_STEPS}->{MASH_STEP}->{STEP_TEMP};
} elsif (ref $recipe->{MASH}->{MASH_STEP} eq 'ARRAY') {
    @recipe_mash_steps = @{$recipe->{MASH}->{MASH_STEP}};
    $mashin_temp = $recipe->{MASH}->{MASH_STEP}->[0]->{STEP_TEMP};
} else {
    @recipe_mash_steps = $recipe->{MASH}->{MASH_STEP};
    $mashin_temp = $recipe->{MASH}->{MASH_STEP}->{STEP_TEMP};
}
my $i = 0;
die "No mash steps found" unless (scalar @recipe_mash_steps > 0);

foreach my $mash (@recipe_mash_steps) {
    next if (defined $mash->{TYPE}
             and
             (
              $mash->{TYPE} ne 'Infusion' and
              $mash->{TYPE} ne 'Sparge'));
    $mash_steps [$i++] = [$mash->{STEP_TEMP}, $mash->{STEP_TIME}];
}
my $mash_steps_string = join '', map {sprintf "X%dX%d", $_->[0], $_->[1]} @mash_steps;

my $boil_time = $recipe->{BOIL_TIME} || 60;
my $boil_temp = 100;

my @hop_additions = (0,0,0,0,0,0); # Initialize hop additions
$i = 0;

my @hop_steps;

if (ref $recipe->{HOPS}->{HOP} eq 'ARRAY') {
    @hop_steps = @{$recipe->{HOPS}->{HOP}};
} else {
    @hop_steps = $recipe->{HOPS}->{HOP};
}

# Herb additions
if (ref $recipe->{MISCS}->{MISC} eq 'ARRAY') {
    push @hop_steps, @{$recipe->{MISCS}->{MISC}};
} else {
    push @hop_steps, $recipe->{MISCS}->{MISC};
}
foreach my $hop (sort {$b->{TIME} <=> $a->{TIME}} @hop_steps) {
    next unless ($hop->{USE} eq 'Boil');
    next if grep {$hop->{TIME} == $_} @hop_additions; # Don't repeat ourselves
    @hop_additions[$i++] = $hop->{TIME};
}

my $hop_steps_string = join '', map {sprintf "X%d", $_} @hop_additions;

my $recipe_string = sprintf "%dX%d%sX%dX%d%s.%s",
    $recipe_no,
    $mashin_temp,
    $mash_steps_string,
    $boil_time,
    $boil_temp,
    $hop_steps_string,
    $recipe_name;
    #uri_escape($recipe_name);
printf "Recipe:\n$recipe_string\n" if $debug;


if ($speidel) {
    my $ua = LWP::UserAgent->new;
    my $response = $ua->post
        (
         'http://'.$speidel.'/rz.txt',
         {
          rz => $recipe_string,
         },
        );
    if ($response->is_success) {
        print $response->decoded_content; # or whatever
    } else {
        die $response->status_line;
    }
} else {
    print "$recipe_string\n";
}
