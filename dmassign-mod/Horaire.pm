package Horaire;
use Moose;
use Moose::Util::TypeConstraints;
use CreneauHoraire;
use Modulation;

### See (man "perl5180delta"). FIXME some day.
no if $] >= 5.018, warnings => "experimental::smartmatch";

has Creneaux => ( is => 'rw', isa => 'ArrayRef[CreneauHoraire]', default => sub { [] }, lazy => 1);

## one 'Horaire' is a list of 'CreneauHoraire'

## add one CreneauHoraire to the current object.
sub addCreneau {
  my $object = shift;
  my $creneau;
  if (@_ == 1) { #ref to existing object OR ref to a hash for
                 #constructing one. Uselessly general.
    $creneau = shift;
    $creneau = CreneauHoraire->new($creneau) unless ref $creneau eq "CreneauHoraire";
  } else { #presumably an actual hash
    $creneau = CreneauHoraire->new(@_);
  }
  push @{$object->Creneaux}, $creneau;
}

## Method of one horaire that takes another Horaire as argument, and
## return the intersections as a list of Creneaux in list context, or
## the number of intersections (every week counts for one separate
## intersection) in scalar context.
sub clashp {
  my $hor1 = shift;
  my $hor2 = shift;
  my @intersections;
  ## FIXME: this assumes all Creneau are disjoint (otherwise the
  ## number will grow for no good reason)
  foreach my $creneau1 (@{$hor1->Creneaux}) {
    foreach my $creneau2 (@{$hor2->Creneaux}) {
      push @intersections, $creneau1->clashp($creneau2);
    }
  }
  if (wantarray) {
    return @intersections;
  } else {
    map { @{$_->weeks} } @intersections; # spell out every intersection so that they can be counted.
  }
}

## Print one Horaire, sorted by day number (all mondays together,
## etc.) then chronologically.
sub print {
  my $object = shift;
  my @list = @{$object->Creneaux};
  @list = sort { ($a->numericaldayofweek <=> $b->numericaldayofweek) or
                   ($a->begin->absolute <=> $b->begin->absolute) } @list;
  return join ("\n", map { $_->print() } @list);
}

sub printlatex {
  my $object = shift;
  my $result = $object->print;
  $result =~ s/\n/\\\\\n/mg;
  return $result;
}

## Determine the true quadri for Horaire. Results is : Q1, Q2 or "" (meaning either both or none.)
sub quadri {
  my $object = shift;
  my $nowarn = shift;
  my @creneaux = @{$object->Creneaux};
  return "" unless @creneaux;
  my $result = $creneaux[0]->quadri;
  if (grep { not ($_->quadri eq $result) } @creneaux) {
    $DB::single = 1;
    unless ($nowarn) {
      print STDERR "Can't determine quadri for given Horaire -- This should not happen\n";
      printf STDERR "%s\n", $_->raw for @creneaux;
      printf STDERR "----\n";
    }
    ## This happened once because there was a mismatch between the
    ## advertised quadri in the Mnemo/NRE/foo/quadri name and the
    ## actual planned weeks.
    ## MATHF109/18412/EXE/Q1,#SPLUS3AC13B,Mathématiques,MATHF109/18412,Coché,21-23,jeudi,16:00:00,02:00,,,GEOL1,"Bruss, F Thomas; Dutrifoy, Alexandre",MATHF109

    ## This also happens when the task in repartition.txt doesn't
    ## specify which of Q1 or Q2 it is for and course spans accross
    ## the two.

    ## FIXME: not sure the above two are still true, because we only
    ## rely on the schedule, not the advertised quadri.

    return "";
  } else {
    return $result;
  }
}

## Take a week number, and return a new object that matches all
## Creneaux in current Horaire that have an occurrence in that week.
## IOW, restrict Horaire to current week.
sub schedule_for_week {
  my $obj = shift;
  my $week = shift;
  return new(Creneaux => [ grep { $week ~~ $_->weeks } @$obj ]);
}

sub by_week {
  # return a ref to a hash table like so : $table{$week}{$dow} = list
  # of creneau at that moment. Useful to print a calendar for each
  # week.
  my $obj = shift;
  my %table;
  foreach my $creneau (@{$obj->Creneaux}) {
    foreach my $week (@{$creneau->weeks}) {
      $table{$week}{$creneau->dayofweek} //= [];
      push @{$table{$week}{$creneau->dayofweek}}, $creneau;
    }
  }
  return \%table;
}

sub totalhms {
  my $object = shift;
  my $result = HMS->new(0);
  foreach my $creneau (@{$object->Creneaux}) {
    $result = $result->add($creneau->totalhms)
  }
  return $result;
}

no Moose;
__PACKAGE__->meta->make_immutable;
