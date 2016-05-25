package CreneauHoraire;
use Moose;
use Moose::Util::TypeConstraints;
use HMS;

### See (man "perl5180delta"). FIXME some day.
no if $] >= 5.018, warnings => "experimental::smartmatch";

our %daytonum = (dimanche=>0, lundi=>1, mardi=>2, mercredi=>3, jeudi=>4, vendredi=>5, samedi=>6) ;
our @numtolongday = ("Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi") ;
our @numtoshortday = ("Di.", "Lu.", "Ma.", "Me.", "Je.", "Ve.", "Sa.") ;

has raw => ( is => 'ro' );
has dayofweek => ( is => 'ro', isa => enum([qw /lundi mardi mercredi jeudi vendredi samedi dimanche/]), required => 1);
has begin => ( is => 'ro', isa => 'HMS');
has end => ( is => 'ro', isa => 'HMS');
has duration => ( is => 'ro', isa => 'HMS');
has rawweeks => ( is => 'ro', isa => 'Str');
has weeks => ( is => 'ro', isa => 'ArrayRef[Int]');
has auditorium => ( is => 'ro', isa => 'Str');


# this isn't exactly pretty, perhaps we should make different
# constructors ?
around BUILDARGS => sub {
  my ($orig, $class, %href) = @_;
  ## FIXME: we use the fact that we never call this constructor with,
  ## e.g. begin and end.
  ## FIXME: make begin, end and duration behave when one is changed.
  ## This would work by defining a different setter method. I'm not
  ## sure if this can be done easily.
  foreach (qw/begin duration end/) { 
    $href{$_} = HMS->new($href{$_}) if exists $href{$_};
  }
  $href{begin} = $href{end}->rem($href{duration}) unless exists $href{begin};
  $href{end} = $href{begin}->add($href{duration}) unless exists $href{end};
  $href{duration} = $href{end}->rem($href{begin}) unless exists $href{duration};
  $href{weeks} = _expand_weeks ($href{rawweeks}) unless exists $href{weeks};
  $href{rawweeks} = _compactify_weeks ($href{weeks}) unless exists $href{rawweeks};

  ## assert:
  die unless $href{end}->absolute eq $href{begin}->add($href{duration})->absolute;
  # die unless $href{weeks} eq _expand_weeks($href{rawweeks});

  return $class->$orig(%href);
};

sub _expand_weeks {
  my $weeks = shift;
  my $numberre = qr/\s*(\d+)\s*/s;
  my @weeks;
  # $weeks =~ q/\d+(-\d+)? *(, *\d+(-\d+)?)*/ or die "Unparsable weeks string: $weeks";
  foreach my $range (split '[,;]', $weeks) {
    if ($range =~ /^$numberre$/) {
      push @weeks, $1;
    } elsif ($range =~ /^$numberre-$numberre$/) {
      die "Unparsable range: $range" unless $1 <= $2;
      push @weeks, $1 .. $2;
    } else {
      die "Unprasable weeks string: $weeks";
    }
  }
  return \@weeks;
}
# see examples
sub _compactify_weeks {
  # sub test(&$$) {
  #   my ($code, $value, $result) = @_;
  #   printf "Test %s\n", ($code->($value) eq $result) ? "passed" : "failed";
  # }
  # test (\&compactifyweeks, [1,4,5,6,7,10], "1, 4-7, 10");
  # test (\&compactifyweeks, [1..10], "1-10");
  # test (\&compactifyweeks, [1..11], "1-11");
  my $aref = shift;
  my @array = sort { $a <=> $b } @$aref;
  return "" unless @array;

  my ($previous, $result);
  $previous = $result = shift @array;
  foreach my $week (@array) {
    $result .= "-$previous, $week" unless $week == $previous + 1;
    $previous = $week;
  }
  $result .= "-$previous";
  # At this point, $result is of the form "1-1, 3-4" ;
  # we now make 1-1 into just "1":
  $result =~ s/(\d++)-\1(?!\d)/$1/g; # the non-backtracking ++
                                     # operator removes the need for a
                                     # lookbehind.
  return $result;
}


sub clashp {
  # Return the number of weeks of intersections for $obj1 and $obj2 (of
  # type CreneauHoraire)
  my $obj1 = shift;
  my $obj2 = shift;
  die unless ref $obj2 eq __PACKAGE__; # FIXME: is this good wrt
                                       # inheritance ? # why do we
                                       # want to check this, we should
                                       # rely on the caller not doing
                                       # silly things. perhaps compare
                                       # with ref $obj1 ??
  my %intersection; # make the result a CreneauHoraire.

  # if dow is different, no intersection.
  return unless $obj1->dayofweek eq $obj2->dayofweek;
  $intersection{dayofweek} =  $obj2->dayofweek;

  # if there's an intersection, it's in the common weeks, so we compute them.
  $intersection{weeks} = [ grep { $_ ~~ @{$obj2->weeks}} @{$obj1->weeks} ];
  return unless @{$intersection{weeks}};

  # now we have same dow and common weeks, see if there's an actual intersection.
  if ($obj1->begin->absolute < $obj2->begin->absolute) {
    return if ($obj1->end->absolute <= $obj2->begin->absolute); # $obj1 is before $obj2
    $intersection{"begin"} = $obj2->begin;
  } else {
    return if ($obj2->end->absolute <= $obj1->begin->absolute); #$obj2 is before $obj1
    $intersection{"begin"} = $obj1->begin;
  }
  # there's an intersection. Compute the end time.
  $intersection{"end"} = ($obj1->end->absolute < $obj2->end->absolute ? $obj1->end : $obj2->end);

  my $intersection = __PACKAGE__->new(%intersection);
  return $intersection;
}
sub numericaldayofweek {
  my $object = shift;
  return $daytonum{$object->dayofweek};
}
sub print {
  my $object = shift;
  my $options = shift;
  my $total_heures = "";
  if ($options->{"total_heures"}) {
    $total_heures = " = " . $object->totalhms->printHM;
  }
  return $numtoshortday[$daytonum{$object->dayofweek}] . " : " . $object->begin->printHM . "-" . $object->end->printHM . " (" . $object->rawweeks . ")" . $total_heures;
}
sub quadri {
  my $object = shift;
  ## FIXME: hardcoding is bad, I guess. Also, what with exams and such ?
  my @Q1 = ( 1 .. 14 );
  my @Q2 = ( 21 .. 35 );
  my @weeks = @{$object->weeks};
  my $hasQ1; my $hasQ2;
  if (grep $_ ~~ @Q1, @weeks) {
    $hasQ1 = 1;
  }
  if (grep $_ ~~ @Q2, @weeks) {
    $hasQ2 = 1;
  }
  if ($hasQ1 && $hasQ2) {
    return "";
  } elsif ($hasQ1) {
    return "Q1";
  } elsif ($hasQ2) {
    return "Q2";
  } else {
    warn "Can't determine which quadri these weeks belong to: @weeks";
  }
}
sub totalhms {
  my $object = shift;
  return HMS->new(($object->duration->absolute) * (scalar @{$object->weeks}));
}

no Moose;
__PACKAGE__->meta->make_immutable;
