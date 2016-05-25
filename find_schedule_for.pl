#!/usr/bin/env perl

## Authors:
## Nicolas Richard.

# The following contains object (classes) definitions
use Horaire;
use CreneauHoraire;
use feature qw (say);


binmode STDOUT, ":encoding(UTF-8)"; # spit utf8 to terminal
binmode STDIN, ":encoding(UTF-8)"; # accept utf8 from stdin
use utf8; # allow for utf8 inside the code.
use strict;
use warnings;
use Try::Tiny;
use Text::CSV;
use MyLaTeX;

my ($horaire_f, $groups, $wanted_weeks);

while (defined($_ = shift)) {
  if  (/^--groups$/) {
    $groups = shift;
  }
  elsif  (/^--weeks$/) {
    $wanted_weeks = shift;
    $wanted_weeks = CreneauHoraire::_expand_weeks ($wanted_weeks) ;
  }
  else {
    unless (-f $_) {
      die "File doesn't exist: $_\n";
    }
    $horaire_f = $_;
  }
}

$horaire_f = "sciences.txt" unless $horaire_f;
my $horaire = Horaire->new ();

my $csv = Text::CSV->new( { binary => 1 } ) and open my $fh, "<:encoding(UTF-8)", $horaire_f or die "Cannot open file: $horaire_f";
## throw header line away
$csv->getline($fh);

while (my $row = $csv->getline($fh)) {
  my ($name, # mnemonique/NRE/EXM|PED|THE|EXE/Q1|Q2
      undef, # m!#SPLUS......!
      undef, # Full course name
      undef, # mnemonique/NRE ## useless
      $coche, # "Coché" ou "Décoché" : skip if Décoché.
      $weeks, # something like [:num:](-[:num:]+)?(; [:num:](-[:num:]+)?)?
      $dayofweek, # "lundi" "mardi" "mercredi" "jeudi" "vendredi" "samedi" ou ""
      $beginhour, # H:M:S
      $duration, # H:M
      $auditorium, # nom de salle
      undef, # teacher list: Lastname, Firstname(; Lastname, Firstname)*
      $studentset, # Set(;Set)* où Set =~ ([A-Z]{4}\d)[^;]* ## FIXME : this
                   # isn't true, e.g. IRBA4S-A PINT4G1 MIN3CRIM11 COMM5UP, etc...
      undef, # usually, same as teacher list ## useless ?
      undef, # mnemonique ## useless ?
     ) = @$row;

  # skip those that should be skipped.
  next if $coche eq "Décoché";

  my @studentset =
    map {
      s/ *$//; $_
      }
      split /;/, $studentset;
  #  MyDebug::suspicious($row->[0],"No studentset") unless @studentset;

  next unless (grep { /$groups/ } @studentset);
  my $creneau = CreneauHoraire->new(
                                    raw => $csv->string(), ## for debugging purpose.
                                    rawweeks=> $weeks,
                                    dayofweek => $dayofweek,
                                    begin => $beginhour,
                                    duration => $duration,
                                    auditorium => $auditorium
                                   );
  next unless (grep { $_ ~~ @{$wanted_weeks} } @{$creneau->weeks});
  $horaire->addCreneau($creneau);

  # foreach my $associatedtask (@$candidates) {
  #   $associatedtask->horaire->addCreneau($creneau);
  # }
}


my @weeks =  (1,2,3,4,5,6,7,8,9,10,11,12);
my @dows = (qw/lundi mardi mercredi jeudi vendredi samedi/);
my %table = %{$horaire->by_week()};

sub leavesmap {
  my ($sub, $href) = @_;
  my %result = map {
    my $value = $href->{$_};
    if (ref $value eq 'HASH') {
      $_ => leavesmap($sub,$value);
    } else {
      $_ => $sub->($value);
    }
  } keys %$href;
  return \%result
}

# for my $week (@weeks) {
#   print $week;
#   for my $dow (qw/lundi mardi mercredi jeudi vendredi samedi/) {
#     print "&";
#     $DB::single=2;
#     my $creneaux = $table{$week}{$dow};
#     if ($creneaux and @$creneaux) {
#       print join "\\\\",
#         map  {
#           $_->begin->printHM() . "--" . $_->end->printHM() ;
#         }
#         @$creneaux;
#     }
#   }
#   print "\\\\\n";
# }

my $foo = sub {
             my $aref = shift;
             my @array = map {
               $_->begin->printHM() . "--" . $_->end->printHM() ;
             } @$aref;
             array_ref_to_vertical_table(\@array)
           };
my $hash = leavesmap($foo , \%table);
my $string = pretty_print_2D_table($hash, \@weeks, \@dows);
print $string;


1;
