package Teacher;
use Moose;
use Moose::Util::TypeConstraints;
use utf8; # allow for utf8 inside the code.
use List::Util qw(first);

### See (man "perl5180delta"). FIXME some day.
no if $] >= 5.018, warnings => "experimental::smartmatch";

has raw => (is => 'ro');
has shortname => ( is => 'ro', isa => 'Str' );
has fullname => ( is => 'ro', isa => 'Str' );
has email => ( is => 'ro', isa => 'Maybe[Str]' );
has initials  => ( is => 'ro', isa => 'Str' );
has status => ( is => 'ro', isa => enum ([qw(0 1 2 3 4 5 6 7 8 9)]) );
has tasks => ( is => 'rw', isa => 'ArrayRef', default => sub { []; }, lazy => 1);
has cma => ( is => 'ro', isa => 'Maybe[Str]' );
has known_courses => ( is => 'rw', isa => 'ArrayRef', default => sub { []; }, lazy => 1);

## CMA par défaut en fonction du statut. En eq-th.
my @defaultcmas =
  (
   30,     # 0 = assistant intérimaire/élève assistant
   120,    # 1 = assistant
   24,     # 2 = doctorant non-assistant (p.ex. FRIA ou aspirant FNRS)
   24,     # 3 = chercheur (postdoc, chargé de recherche)
           ## Permanents:
   24,     # 4 = chercheur (chercheur qualifié)
   120,    # 5 = chargé de cours
   120,    # 6 = professeur
   120,    # 7 = professeur ordinaire
   24,     # 8 = prof. de l'université
   0       # 9 = prof. extérieur
  );

## Donner le "score" de la personne par rapport à la charge des gens
## dans @$others.
sub meanscore {
  my $teacher = shift;
  my $others = shift;
  # die "Comparer qqn à une moyenne dans laquelle il n'est pas ? hmm..."
  #   unless ($teacher ~~ @$others); # smart matching won't work on objects and lists of objects.
  my $teacher_score = $teacher->score();
  my $mean_score = 0;
  $mean_score += $_->score() foreach @$others;
  $mean_score /= scalar @$others;
  $teacher_score -= $mean_score;
  return sprintf "%.2f", $teacher_score;
}

## Donner le "score" de la personne par rapport à sa charge actuelle.
sub score {
  my $teacher = shift;
  my $charge = $teacher->totalcount(0, "skew")->eq_th() || 0;
  my $cma = $teacher->cma || 1; # coefficient multiplicateur
  $cma *= $defaultcmas[$teacher->status]; # multiplié par la charge max
  my $score = $cma ? ($cma - $charge) / $cma : "erreur";
  return $score;
}

sub admintasks {
  my $object = shift;
  return grep { ref $_ eq "AdministrativeTask" } @{$object->tasks};
}
sub teachingtasks {
  my $object = shift;
  my $type = shift;
  return grep { ref $_ eq "TeachingTask" and (not (defined $type) or ($_->thorex eq $type)) } @{$object->tasks}
}
sub addtask {
  my $object = shift;
  my $task = shift;
  push @{$object->tasks}, $task;
  return $task;
}
sub printgpdata {
  my $object = shift;
  return ($object->totalcount->eq_th - $object->totalcount->th) . " " . $object->totalcount->th;
}
sub printgpplot {
  my $object = shift;
  return sprintf "set label \"%s\" at %s,%s", $object->initials, ($object->totalcount->eq_th - $object->totalcount->th), $object->totalcount->th + 10; # FIXME: 10=?
}
sub printconflicts {
  my $object = shift;
  my $tasks = [ $object->teachingtasks() ];
  my $result = "";
  while (@$tasks) {
    my $task = shift @$tasks;
    my $conflictingtasks = "";
    foreach my $othertask (@$tasks) {
      my $clash = $othertask->clashp($task);
      if ($clash) {
        $conflictingtasks .= sprintf ("\n->%s ($clash)", $othertask->almostraw);
      }
    } 
    if ($conflictingtasks) {
      $result .= $task->almostraw . $conflictingtasks . "\n";
    }
  }
  if ($result) {
    $result = sprintf "Teacher %s has conflicts:\n$result\n", $object->fullname;

  }
  return $result;
}
sub printreport {
  ## Imprime le tableau de l'enseignant pour dans la première partie du rapport.
  my $object = shift;
  my $options = shift;
  my $result = "";
  my $ttasks = $object->printteachingtasks($options);
  my $atasks = $object->printadmintasks;
  ## my $conflicts = $object->printconflicts; ## FIXME: unused ?

  if ($ttasks or ($atasks and $options->{admintasks})) {
    ## We need to use this weak form of \raggedright. that doesn't
    ## change the definition of \\.
    $result .= "\\par\\noindent\n";
    $result .= '\\begin{tabularx}{\\textwidth}{c>{\\rightskip 0pt plus 1fil}X}' . "\n";
    $result .= $object->printgraph();
    $result .= "&";
    $result .= $ttasks;
    $result .= $atasks if $options->{admintasks};
    $result .= $object->printhorairelatex($options) . "\n" if $options->{horaire};
    $result .= "\\end{tabularx}\n";
    $result .= "\\medskip\n";
    # if ($ttasks) {
    #   my %seen = ();
    #   my @unique = grep { ! $seen{ $_ }++ } $object->teachingtasks;
    #   $result .= "\\begin{tabularx}{\\linewidth}{lX}\n";
    #   $result .= "Cours & Collègues\\\\\n";
    #   foreach (@unique) {
    #     $result .= $_->course->print() . "\\\\\n"
    #   }
    #   $result .= "\\end{tabularx}\n";
    # }
  } else {
   # $result .= sprintf "%s n'a aucune tâche assignée\n", $object->fullname;
  }
  return $result;
}

## Méthode
## IN: nil
## OUT: objet Horaire
sub horaire {
  my $object = shift;
  my $listedescreneaux = Horaire->new();
  foreach (map { @{$_->horaire->Creneaux } } $object->teachingtasks()) {
    $listedescreneaux->addCreneau($_)
  }
  return $listedescreneaux;
}
sub printhoraire {
  my $object = shift;
  return $object->horaire->print();
}
sub printhorairelatex {
  my $object = shift;
  my $options = shift;
  my @horaire;
  my $result = "";
  foreach my $task ($object->teachingtasks()) {
    next if $task->mnemonic eq "INDISPONIBLE";# FIXME: hardcoded; is that bad ?
    if (not $options->{quadri}
        or not $task->quadri
        or $task->quadri eq $options->{quadri}) {
      ## Ajoute chaque créneau pour le cours en question dans @horaire
      push @horaire, map {
        [ $task, $_ ];
      } @{$task->horaire->Creneaux };
    }
  }
  ## FIXME: Copy pasted from Horaire.pm:
  @horaire = sort { ($a->[1]->quadri cmp $b->[1]->quadri)
                      or ($a->[1]->numericaldayofweek <=> $b->[1]->numericaldayofweek)
                        or ($a->[1]->begin->absolute <=> $b->[1]->begin->absolute) }
    @horaire;
  if (@horaire) {
    # Affiche chaque Horaire & Tâche
    my $lineprinter = sub { my $object = shift;
                            sprintf "%s & %s",  $object->[1]->print({ total_heures => 1}), $object->[0]->course->mnemonic . "/" . $object->[0]->group;
                          };
    $result .= sprintf "\\begin{teacherhoraire}{%s}\n", $object->fullname;
    $result .= join ("\\\\\n", map { $lineprinter->($_) } @horaire) . "\\\\\n";
    $result .= "\\end{teacherhoraire}";
  }
  return $result;
}

sub printteachingtasks {
  my $object = shift;
  my $options = shift;
  my $ttasksTHE = [ $object->teachingtasks("THE") ];
  my $ttasksEXE = [ $object->teachingtasks("EXE") ];
  my $result = "";
  # my $score = $object->score // ""; # FIXME: utiliser meanscore ?
  my $score = ""; ## FIXME: pour l'instant on n'affiche pas. Enlever ceci pour afficher!
  if (@$ttasksTHE or @$ttasksEXE) {
    $result .= sprintf "\\hypertarget{%s}{}\\begin{teacher}[%s]{%s}\n", $object->shortname, $score, $object->fullname;
    do {
      my $options = $options;
      $options->{"coord"} = ($_->course->coordinateur and ($_->course->coordinateur eq $object));
      $result .= $_->printtaskline($options) # unless $_->void()
    } foreach @$ttasksTHE;
    $result .= sprintf "\\hline\n" if @$ttasksTHE and @$ttasksEXE;
    do { $result .= $_->printtaskline($options) unless $_->void() } foreach @$ttasksEXE;
    $result .= "\\hline\n";
    my $total = $object->totalcount;
    $result .= sprintf "Totaux & & %s & %s & %s & %s h-th & \\\\\n", (map { $total->$_ } (qw{th ex tp eq_th}));
    $result .= "\\end{teacher}\n";
    local $\ = "\n";
  }
  return $result;
}
sub printadmintasks {
  my $object = shift;
  my $atasks = [$object->admintasks()];
  my $result = "";
  if (@$atasks) {
    $result .= sprintf "\\begin{teacheradmin}{%s}\n", $object->fullname;
    $result .= $_->printtaskline foreach @$atasks;
    $result .= "\\end{teacheradmin}\n";
  }
return $result
}
sub printgraph {
  my $object = shift;
  my %teacher_count = ( SE => $object->totalcount("SE"), BA => $object->totalcount("BA"), MA => $object->totalcount("MA") );
  my @list_of_counts = map { $teacher_count{$_}->{"th"}, ($teacher_count{$_}->eq_th - $teacher_count{$_}->th); } (qw/SE BA MA/);
  if (first { $_ > 500 } @list_of_counts) {
    return "(No graph here)";
  } else {
    return sprintf "\\nicegraph{%s}{%s}{%s}{%s}{%s}{%s}",
      @list_of_counts;
  }
}

sub totalcount {
  my $object = shift;
  my $restrictto = shift // ""; # optional restriction.
  my $skew = shift; # If true, give higher impact to courses never
                    # given before.
  my @knowncourses = @{$object->known_courses()};
  my $restriction;
  if ($restrictto eq "SE") {
    $restriction = sub {
      return $_->course->status eq 2;
    };
  } elsif ($restrictto =~ /(BA|MA)/) {
    $restriction = sub {
      return (not $_->course->status eq 2) && ($_->course->cycle eq $restrictto);
    };
  } elsif ($restrictto =~ /(Q1|Q2)/) {
    $restriction = sub {
      my $quadri = $_->quadri_compute();
      return ($quadri eq $restrictto);
    };
  } else {
    $restriction = sub { return 1; };
  }
  my $ref = Modulation->new("0/0/0");
  foreach
    my $task ( grep
               { ref $_ eq "TeachingTask"
                   and $restriction->();
               } @{$object->tasks})
    {
      my $modulation = $task->modulation->meta->name->new($task->modulation->rawstring);
      if ($skew and not knowncourse($task->course, \@knowncourses)) {
        $modulation->mul(1.6); ## FIXME do not hardcode?
      }
      $ref->add($modulation);
    }
  return $ref;
}

sub knowncourse {
  ## "Vérifie si $course est dans @$knowncourses (= une liste de mnémonique ou mnémonique/quadri)"
  my $course = shift;
  my $mnemonic = $course->mnemonic;
  my $mnemonicquadri = $mnemonic . "/" . $course->quadri;
  my $knowncourses = shift;
  for my $knowncourse (@$knowncourses) {
    if (($mnemonic eq $knowncourse)
        or ($mnemonicquadri eq $knowncourse)) {
      return $course;
    }
  }
  return 
}

__PACKAGE__->meta->make_immutable;
