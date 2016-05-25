#!/usr/bin/env perl

## Authors:
## Samuel Fiorini (C++ version),
## Nicolas Richard (translation to Perl).

use File::Basename;

# This allows us to find our modules !
BEGIN {
  my (undef, $libdir) = fileparse($0);
  unshift @INC, "$libdir/dmassign-mod";
}
## FIXME: It doesn't work if we're called via a symlink to the actual perl file.
## FIXME: vérifier pragma lib, ou alors "use dmassign-mod::module"
# The following contains object (classes) definitions
use Modulation; ## module d'appoint
use Horaire; ## module d'appoint
use MyDebug;

## chaque ligne dans ... donne lieu à un objet de ce type :
use AdministrativeTask; ## taches.txt
use Course; ## cours.txt
use Teacher; ## profs.txt
use TeachingTask; ## repartition.txt

## ==Fonctionnement du matching TeachingTask-horaire==

## L'idée est que pour chaque ligne de l'horaire, on vérifie d'abord
## si le cours nous concerne (i.e. on a au moins une tâche qui
## correspond au mnémonique). Si oui, on essaye de lui trouver quelle
## tâche c'est (et si on ne trouve pas, on se plaint.) -- Cette
## approche permet d'avoir un fichier d'horaire qui contient plus de
## cours que nécessaire, tout en détectant aussi si des tâches sont à
## l'horaire mais que personne n'est prévu. Mais parfois, on assigne
## qqn à un tp sans que la théorie nous concerne (e.g. INFOF205), ou
## qqn à un cours sans que les TPs nous concernent (e.g. MATH S
## 101/102). Dans ce cas on ignore les lignes de l'horaire
## correspondant à ce qui ne nous intéresse pas, via
## @skipscheduledlines ci-dessous.


## FIXME : should be possible to add weight for certain course/teacher combinations
## FIXME : should be possible to relieve certain teachers (e.g. when writing the thesis)

my $Th_Exe_factor = 2; ## FIXME: this can be given on a
                       ## course-by-course basis within
                       ## TeachingTask.pm, but then things break.
my $annee_aca = "";
my $print_verbose_info = 1; ## by default, output more info. Some options turn this off.
our $raw;

## NOTE: 'n' of our groups can be made from 'm' GeHoL groups, and (n,m) can take different values among~:
## (n,m=n) : with easiest case
## (n,1) : only one group on GeHoL (avec plusieurs locaux!) become more than one for us
## (1,m) : mulitple groups on GeHoL (e.g. different years, or one year which has to be made into more than one groups for other purposes e.g. labs) become one for us
## (n,m\neq n) : e.g. MATHF101 (2 groups for us, 3 for gehol)


my %ourgroup2facgroup;

binmode STDOUT, ":encoding(UTF-8)"; # spit utf8 to terminal
binmode STDERR, ":encoding(UTF-8)"; # spit utf8 to terminal
binmode STDIN, ":encoding(UTF-8)"; # accept utf8 from stdin
use utf8; # allow for utf8 inside the code.
use strict;
use warnings;
use Try::Tiny;
use Text::CSV;
use MyLaTeX;
use File::Basename qw/basename/;

### See (man "perl5180delta"). FIXME some day.
no if $] >= 5.018, warnings => "experimental::smartmatch";

# use autodie qw(:all);

sub CSV_map (&$;$) {
  ## Usage: CSV_map BLOCK "filename", "separator"
  ##        CSV_map EXPR, "filename", "separator"
  ## For each non-ignored line, $_ is locally set within BLOCK or EXPR
  ## to the array of its values
  my $code = shift;
  our $filename;
  my $sep;
  ($filename, $sep) = @_;


  ## Check values
  $sep = ";" unless defined($sep);
  open(my $filehandle , "<:encoding(utf8)", $filename) or die "Can't open file: $filename\n";

  ## Local variables
  my $result = [];

  while (<$filehandle>) {
    chomp;
    local $raw = $_; ## DEBUG
    next if /^#/ or /^ *$/;     # skip comments and empty lines
    local $_ = [ split /$sep/, $_, -1 ];

    push @$result, $code->();
  }
  close $filehandle; # in fact unneeded, see perlopentut.
  return @$result;
}
sub objects_array_to_hash {
  #INPUT:
  # 1. a ref to an array of refs to some objects
  # 2. a sub that returns something for each object (for $_ being the object
  #    being looked at)
  # 3. third arg should be true (e.g. "1") if object->key is assumed to be
  #    unique (and we should throw an error if we notice that it is not). This is
  #    $assumeunique.

  # OUTPUT: ref to a new hash table with keys equal to the values of the
  # property, and values are (i) (if $assumeunique is false) a ref to an array
  # of objects whose named property has the value, or (ii) (if $assumeunique is
  # true), values are the actual objects.
  my ($aref, $code, $assumeunique) = @_;
  my $accumulate = not $assumeunique;
  my %result;
  do { # $_ is a reference to an object
    my $key = $code->();
    next unless defined $key;
    if ($accumulate) { # $result{$key} shall hold a ref to an array of
                       # references to objects
      $result{$key} = [] unless exists $result{$key};
      push @{$result{$key}}, $_
    } else { # $result{$key} shall hold a ref to the object
      if (not $result{$key}) {
        $result{$key} = $_
      } else {
        warn "Key has multiple values : $key\n";
        return 0;
      }
    }
  } for @$aref;
  return \%result;
}
sub identity {
  return @_;
}
sub read_line_to_object {
  ## INPUT: a class, a list of keywords for its constructor, and a list of the
  ## corresponding values (we use $_ if third arg is not given.)
  my ($class, $kwlist, $values) = @_;
  $values //= $_; # default value for $values

  my %constructor_arg;
  @constructor_arg{@$kwlist} = @$values;
  return $class->new(%constructor_arg);
}
sub find_teacher_by_shortname {
  return find_object_by_prop ("shortname", @_);
}
sub find_object_by_prop {
  my ($property, $value, $objectarray) = @_;
  my @candidates = grep { $_->$property eq $value } @$objectarray;
  if (scalar @candidates == 1) {
    return shift @candidates;
  } elsif (scalar @candidates < 1) {
    if (($property =~ /^shortname$/)
        and ($value =~ /^XTP-/)) {
      return find_object_by_prop ($property, "XTP", $objectarray);
    } elsif (($property =~ /^shortname$/)
             and ($value =~ /^X-/)) {
      return find_object_by_prop ($property, "X", $objectarray);
    } else {
      return undef;
    }
  } else {
    die "Multiple candidates match the $property/$value pair.";
    return undef;
  }
}


my ($teacheropts, $teachers, @Courses, @Teachers, @TeachingTasks, @AdmTasks);
my $print_teacher_conflicts = 0;
my $print_tasks_conflicts = 0;
my $print_global_report = 0;
my $print_charges = 0;
my $print_suspicious_entries = 0;
my $print_admin_tasks = 0;
my $print_horaire = 0;
my $print_quadri = "";
my $print_format_xls_fac = 0;
my $additionnalschedule_fn = "";
my $skipscheduledlines_fn = "";
my $groups_fn = "";
my $opt_alternance = "";
my $print_emails = 0;
my @files;

my $indir = ".";
my $outdir = "."; # where should all files go.

#FIXME: mettre en place une option de vérification des données pour la
#cohérence (chaque cours a des acti, etc.)

while (defined($_ = shift)) {
  if (/^-([0-9]+)$/) {
    $teacheropts = $1;
  } elsif (/^--teachers$/) {
    $teachers = shift;
  } elsif (/^--alternance$/) {
    $_ = shift;
    if (/^(paire|even)$/) {
      $opt_alternance = 2;
    } elsif (/^(impaire|odd)$/) {
      $opt_alternance = 1;
    } elsif (/^(moyenne|mean)$/) {
      $opt_alternance = "mean";
    } else {
      die "Unrecognized value for option --alternance: $_";
    }
  } elsif (/^--outdir$/) {
    $outdir = shift;
    $outdir =~ s|/$||;
    mkdir $outdir unless -e $outdir;
    die "Couldn't find or create out directory: $outdir" unless -d $outdir;
  } elsif (/^--indir$/) {
    $indir = shift;
    $indir =~ s|/$||;
    die "indir is not a directory: $indir" unless -d $indir;
  } elsif (/^--quiet$/) {
    $print_verbose_info = 0;
  } elsif (/^--teacher-conflicts$/) {
    $print_teacher_conflicts = 1;
  } elsif (/^--task-conflicts$/) {
    $print_tasks_conflicts = 1;
  } elsif (/^--admin-tasks$/) {
    $print_admin_tasks = 1;
    $print_global_report = 1;
  } elsif (/^--teacher-charges$/) {
    $print_charges = 1;
  } elsif (/^--annee-aca$/) {
    $annee_aca = shift;
  } elsif (/^--print-horaire$/) {
    $print_horaire = 1;
    $print_global_report = 1;
  } elsif (/^--no-print-horaire$/) {
    $print_horaire = 0;
  } elsif (/^--quadri$/) {
    $print_quadri = shift;
  } elsif (/^--format-xls-fac$/) {
    $print_format_xls_fac = 1;
  } elsif (/^--report$/) {
    $print_global_report = 1;
  } elsif (/^--additionnal-schedule$/) {
    $additionnalschedule_fn = shift;
  } elsif (/^--skip-scheduled-lines$/) {
    $skipscheduledlines_fn = shift;
  } elsif (/^--groups-file$/) {
    $groups_fn = shift;
  } elsif (/^--print-emails?$/) {
    $print_emails = 1;
  } elsif (/^--help$|^-h$/) {
    printhelp();
    exit 0;
  } elsif (/^--/ and not (-f find_input_file($_))) {
    printhelp();
    die "Unknown option: $_";
  } else {
    my $file = find_input_file($_);
    die "File doesn't exist: $file\n" unless -f $file;
    push @files, $file ;
  }
}

sub find_input_file { my $file = shift; return "$indir/$file"; }

sub printhelp {
  print <<EOF
Usage: perl $0 options [cours.txt profs.txt taches.txt repartition.txt sciences.txt]

Options:
-0123456789         Chaque chiffre correspond à un "type" de membre du dépt :
                    voir les commentaires dans profs.txt pour leur
                    signification.
--teachers <names>  Noms courts de membres (cf repartition.txt) séparés par des
                    virgules, pour n'afficher que l'info qui les concerne
--outdir <dir>      Répertoire où doivent aller les fichiers
--indir <dir>       Répertoire des données (par défaut: .)
--quiet             Ne pas diffuser les messages d'info/erreur
--teacher-conflicts Imprime les conflits pour chaque membre
--task-conflicts    Imprime les conflits entre les taches
--admin-tasks       Imprime les tâches admin dans le rapport (implique --report)
--teacher-charges   Imprime un tableau reprenant les charges des profs
                    sélectionnés
--alternance <opt>  <opt> est l'un de: even, odd, mean. Le nombre
                    d'heure sera alors calculé pour une année paire,
                    impaire ou en moyenne.
--annee-aca <année> L'année aca -- uniquement utilisé dans le graphe du rapport. 
--print-horaire     Imprime l'horaire dans le rapport (implique --report)
--no-print-horaire  N'imprime pas l'horaire même si un rapport est demandé.
--print-emails      Sort une liste d'emails des gens ayant au moins une heure
                    de théorie à prester.
--additionnal-schedule <file>   Utilise un fichier d'horaire supplémentaire (par
                    défaut: additionnal_schedule.txt s'il existe)
--skip-scheduled-lines <file>   Utilise un fichier de ligne horaire à ignorer
                    défaut: skipschedule.txt s'il existe)
--groups-file <file> Mentionne un mapping nos groupes->groupes horaire
                    default: groups.txt s'il existe
--quadri <Q1|Q2>    N'imprime que les taches du quadri sélectionné (uniquement
                    avec --report et --teacher-charges)
--format-xls-fac    Sort un fichier fac-data.csv du style demandé par la fac
--report            Sort les fichiers: all.tex, load.data, load.gnuplot
--help              Le présent texte d'aide

Exemple: perl $0 -0123 --report
EOF
}
# Using _fn for filenames and (later) _fh for filehandles.
my $data_fn = "$outdir/load.data"; # 
my $gnuplot_fn = "$outdir/load.gnuplot";
my (undef, $libdir) = fileparse($0);
my $report_skel_fn = "$libdir/report-skeleton.tex"; # input file
my $loadeps_fn = "load.eps"; # run gnuplot to get this one. Assume we
                             # are in the output dir already !
my $output_csv_fn = "$outdir/fac-data.csv";
my $report_fn = "$outdir/all.tex";


# cours.txt : DESCRIPTION DES COURS RELEVANT DU COLLEGE D'ENSEIGNEMENT
## Format: Mnémo;Crédits(Th/Ex/TP);Nom;BA/MA;Service/Optionnel/Obligatoire;

# Discussion : les cours relevant du collège sont dans cours.txt. Les infos
# "Crédits" et "Nom" sont également dans le catalogue des cours. On peut
# vérifier que ça colle, ou enlever l'info du fichier "cours.txt" et ne garder
# que l'info officielle. Les autres infos (BA/MA et Serv/Opt/obligatoire)
# pourraient être obtenus automatiquement dans une certaine mesure sauf sur le
# caractère "obligatoire", et en plus il faudrait des procédures ad-hoc dans
# certains cas (donné en MA à option ne BA, ou inversement, donné à plusieurs
# sections dont Math, etc.).

# Le fichier cours.txt permet aussi de garder quelques notes informelles sur les
# cours qui disparaissent/arrivent/changent.

# Dans ce fichier on n'a pas le NRE ni les années dans lesquelles le cours est
# donné. Ceci est un peu problématique si on veut vérifier que l'horaire colle à
# ce qu'il faut faire en réalité, cependant fondamentalement ça c'est plutôt
# quand on compare l'horaire avec repartition.txt qu'il faudrait que ça colle. À
# nous de faire en sorte que repartition.txt et l'horaire reflètent le catalogue.

# On devrait les éventuels cotitulaires du cours (pour les tournantes, et pour #
# les cours qui n'ont pas de côté "théorie".)

# profs.txt : LISTE DES ENSEIGNANTS DU DEPARTEMENT
## Format: ID;Nom complet;Initiales;type (assistant, chercheur, etc.)

# Initiales inutiles ? on peut scripter : vérif de l'unicité de l'ID, vérif de
# l'unicité des initiales (ou alors à créer à la volée ?). On peut scripter un
# lien avec PGI et/ou la liste dispo sur le site du dépt et/ou le fichier .xls
# du secrétariat ou tout à la fois.

# on peut ajouter à ce fichier une liste des anciennes affectations (surtout
# pour les assistants) afin de pouvoir en tenir compte comme une charge suppl de
# donner un nouveau TP/cours. Format envisagé: Mnémo1,Mnémo2,etc. On doit
# pouvoir outrepasser cette indication directement dans le fichier de
# repartition.txt en indiquant le poids à donner.

# il faut aussi garder l'info sur l'écriture de thèse, pour l'année concernée.
# le "type" d'enseignant pourrait être adapté pour indiquer un pourcentage de la
# charge nominale de l'enseignant duquel on devrait tenter de s'approcher. i.e.
# "1,90%" serait : "Assistant, à charger de préférence à 90% d'une charge
# d'assistant", et "3,24h" serait : "Chercheur postdoc, à charger de préférence
# à 24h". Le pourcentage est intéressant mais impraticable : tous les assistants
# ne odnnent pas la même chose, etc.

# taches.txt : TACHES ADMINISTRATIVES
## Format: Nom de la tâche/Nombre d'étoiles/Responsable

# Double-emploi avec une liste maintenue par le secrétariat. À quoi sert cette
# liste ? À rien en pratique. Juste pour maintenir la liste des responsables et
# se donner bonne conscience en leur attribuant des étoiles

# repartition.txt : REPARTITION DES TACHES PEDAGOGIQUES
## Format : Th/Exe;Mnémonique;groupe;nombre d'heures;personne affectée

# Chaque ligne correspond à une tâche d'un certain nombre d'heures. À une tâche
# correspond : un type de tâche (Th, Exe, on pourrait ajouter: TP, Excursion,
# Coord), un cours du programme, un groupe (qu'il faudra mapper sur un groupe de
# la fac si il faut un horaire), un nombre d'heures pour l'étudiant (useless? il
# faut que ça match l'horaire et le programme pour bien faire) qu'on pourrait
# transformer en nombre d'heure pour l'enseignant (difficile à estimer?), ou
# alors mettre les deux infos ; et la personne affectée (un enseignant). On
# pourrait aussi ajouter le nombre d'étudiants estimés pour cette tâche. Cela
# fait peu de sens de tenir un historique du nombre d'étudiants pour une tâche
# donnée au vu de la volatilité des différents décrets et du nombre de réformes
# de programmes auxquelles nous devons nous soumettre.

# Il faudrait pouvoir distinguer les cours en alternance, gelés, etc.

# sciences.txt
## Format (CSV): Nom,Clé hôte,Description,Nom du module,Programmé,Semaines
## programmées,Jours programmés,Heure de début (programmée),Durée,Nom de la
## salle allouée,Nom de l'enseignant alloué,Nom de l'ensemble d'étudiants
## alloué,Texte utilisateur 2,Texte utilisateur 4

# catalogue-sciences.csv
## Format: MNEMO,"Intitulé long","ECTS CRS",NRE,"ECTS
## NRE",TH,TP,EX,TPERS,EXC,STG,"TOTAL HRS","ANET ULBDB","Code Majeure","Desc.
## Majeure"

# Ces deux fichiers viennent de l'administration:
# - sciences.txt vient de Pierre Marroy (GeHoL)
# - catalogue-sciences.csv venait de ... ? Pas utilisé dans le script actuellement.

unless (@files) {
#  print STDERR "DEBUG: No files given. Using defaults\n" if $print_verbose_info;
  for (qw!cours.txt profs.txt taches.txt repartition.txt sciences.txt!) {
    my $file = find_input_file ($_);
    die "File not found: $file" unless -f $file;
    push (@files, $file);
  }
  # MyDebug::show_message_and_list ("DEBUG: No files given. Using defaults",@files) if $print_verbose_info;
}
unless ($additionnalschedule_fn) {
  $additionnalschedule_fn = find_input_file("additionnal_schedule.txt");
  # If it doens't exist, don't use it :
  $additionnalschedule_fn = "" unless -e $additionnalschedule_fn;
}
if ($additionnalschedule_fn and not -e $additionnalschedule_fn) {
  die "Fichier d'horaire supplémentaire n'existe pas ", $additionnalschedule_fn;
}
unless ($skipscheduledlines_fn) {
  $skipscheduledlines_fn = find_input_file("skipschedule.txt");
  # If it doens't exist, don't use it :
  $skipscheduledlines_fn = "" unless -e $skipscheduledlines_fn;
}
if ($skipscheduledlines_fn and not -e $skipscheduledlines_fn) {
  die "Fichier de ligne horaires à ignorer n'existe pas ", $skipscheduledlines_fn;
}
unless ($groups_fn) {
  $groups_fn = find_input_file("groups.txt");
  # If it doens't exist, don't use it :
  $groups_fn = "" unless -e $groups_fn;
}
if ($groups_fn and not -e $groups_fn) {
  die "Fichier contenant la traduction de nos groupes vers les groupes de la fac n'existe pas ", $groups_fn;
}

unless ($annee_aca) {
  ## Déterminer l'année académique à partir du répertoire courant.
  ( $annee_aca = `pwd` ) =~ s|.*/([^/]+)$|$1|;
  chomp $annee_aca;
}
if (scalar @files != 5) {
  die sprintf "Wrong number of files. %d given, 6 expected.\n", scalar @files;
}

## Default value
$teacheropts = "0123456789" unless defined $teacheropts;
sub keepteacher {
  ### Return true value if we want to know about teacher (a Teacher object).
  ### FIXME: Possibles usecases:
  ### - Collège d'enseignement (uniquement les titularisation)
  ### - Répartition des exes :
  ###   - Uniquement les EXE (juste comme doc de travail, pour avoir une vue d'ens...? boaf jamais utilisé).
  ###   - Tous (pour pouvoir avoir les titulaires en même temps)
  ###   - Uniquement les assistants (pour savoir si le partage est équitable)
  ### Actuellement la seule possibilité est de splitter sur les types d'enseignants (assistant ou pas, p.ex.)
  ### Il faudrait pouvoir splitter aussi sur le type d'acti (Th ou Exe).
  my $teacher = shift;
  return $teacheropts =~ $teacher->status;
}


## Read files
my ($cours_fn, $prof_fn, $taches_fn, $repartition_fn, $horaire_fn) = @files;

## DOC: Le tableau ci-dessous contient un ensemble de lignes du
## fichier d'horaire à ignorer.
my @skipscheduledlines;
if ($skipscheduledlines_fn) {
  @skipscheduledlines = CSV_map { return $_->[0]; } $skipscheduledlines_fn, ",";
}
if (@skipscheduledlines and $print_verbose_info) {
  MyDebug::show_message_and_list("DEBUG: Some lines from schedule will be skipped.");
}


if ($groups_fn) {
  %ourgroup2facgroup = CSV_map {
    my ($our, $theirs) = @$_;
    if ($theirs) {
      return ($our, qr/$theirs/);
    } else {
      return;
    }
  } $groups_fn;
}


## Read files into perl structures. CSV_map locally sets $_ to an aref
## of fields on current line, and read_line_to_object reads from there.
@Courses = CSV_map {
  chomp @_;
  $_->[1] = Modulation->new("0/0/0"# $_->[1]
                           );
  $_->[5] //= "";
  $_->[6] //= "";
  $_->[7] = $raw; ## DEBUG
  read_line_to_object("Course", [ qw/mnemonic modulation name cycle status quadri alt raw/ ]); # DEBUG: remove raw
} $cours_fn;

@Teachers = CSV_map {
  my ($shortname, $fullname, $initials, $status, $cma, $known_courses, $email) = @$_;
  $known_courses = [ split /,/, $known_courses || "" ];
  $cma =~ s/h$// if $cma;
  Teacher->new(shortname => $shortname,
               fullname => $fullname,
               initials => $initials,
               status => $status,
               email => $email,
               cma => $cma, # charge maximale autorisée.
               known_courses => $known_courses,
               raw => $raw); # DEBUG: remove raw
} $prof_fn;

## Retain only those we really want.
if ($teachers) {
  $teachers = [ split (",", $teachers) ];
  @Teachers = grep { $_->shortname ~~ @$teachers } @Teachers
}

# This is a list of tasks + person in charge of the task. Now is a good time to
# lookup that person in our Teachers base.
@AdmTasks = CSV_map {
  $_->[3] = $raw; ## DEBUG
  our $owner; *owner = \$_->[2]; ## Make $owner an alias for the
                                 ## corresponding element in @$_
  if (my $ownerobject = find_teacher_by_shortname($owner, \@Teachers)) {
    $owner = $ownerobject;
  } else {
    print STDERR "DEBUG: Cannot find teacher: $owner\n" if $print_verbose_info;
    return;
  }

  my $task = read_line_to_object("AdministrativeTask", [ qw/name level owner raw/ ]); # DEBUG: remove raw

  $owner->addtask($task);
  return $task;
} $taches_fn;

sub parse_repartition {
  my $fn = shift;
  CSV_map {
    my %constructor; # we don't rely on read_line_to_object because we
    # need to transform things a bit
    $constructor{"raw"} = $raw; ## DEBUG
    $constructor{"thorex"} = { "Th" => "THE", "Exe" => "EXE" }->{$_->[0]}
      or die "Expected Th or Exe but got: $_->[0]"; # transform Th to THE and Exe
    # to EXE.
    ## One attribute == one info, so split those MATHF101/Q1 in two
    ## pieces. FIXME: should we split MATHF101 into [ "MATH" "F" "101" ]
    ## ? if so, what with the CQPEDA and others ?
    my ($mnemo,$quadri) = $_->[1] =~ m!([^/]+)(?:/(Q1|Q2))?$!
      or die "Unexpected task (not mnemo/quadri) : $_->[1]";
    $constructor{"quadri"} = $quadri // 0;

    my @courses_candidates = grep { $_->mnemonic eq $mnemo } @Courses;
    unless (@courses_candidates == 1) {
      die "Cannot associate TeachingTask " . $mnemo . " to course.",
    }
    $constructor{"course"} = $courses_candidates[0];

    my $group = $_->[2];
    $constructor{"group"} = $group;

    # We only need $ourgroup2facgroup{$group} later on, but IMO it makes
    # more sense to test that right now.
    # printf STDERR "Unknown group: $group\n" unless exists $ourgroup2facgroup{$group} or not $print_verbose_info;

    my $modulation = Modulation->new($_->[3]);
    my $alt = $constructor{"course"}->alt;
    if ($opt_alternance and $alt) {
      if ($opt_alternance eq "mean") {
        $modulation->mul(0.5);
      } elsif (($alt == 2 and $opt_alternance == 1) or
               ($alt == 1 and $opt_alternance == 2)) {
        $modulation = $modulation->mul(0);
      } elsif ($alt == $opt_alternance) {
        1;
        ## All good.
      } else {
        die "Oh wait this should not happen right ? Invalid value somewhere !
Look at it: $alt, $opt_alternance (task: $raw)"
      }
    }
    $constructor{"modulation"} = $modulation;
  

    unless ($constructor{"owner"} = find_teacher_by_shortname($_->[4], \@Teachers)) {
      our $filename;
      print STDERR "DEBUG: Cannot find teacher for TeachingTask ($filename:$.) : $_->[4]\n" if $print_verbose_info;
      return;
    }

    my $task = TeachingTask->new(%constructor);
    $courses_candidates[0]->addtask($task);
    $constructor{"owner"}->addtask($task);
    return $task;
  } $fn;
};

## analyse de repartition.txt
@TeachingTasks = parse_repartition($repartition_fn);



## We'll now be reading the "horaire" file ; now is a good time to
## match every schedule line with the tasks to which it pertain, but
## that requires some heuristic. In particular we will need to find
## all tasks matching a given mnemonic, so we convert @TeachingTask
## into a hash : for every name, associate an aref of objects that
## have it as their $_->name

my $TeachingTasks = objects_array_to_hash(\@TeachingTasks,sub { $_->mnemo }, 0)
  or die "Unexpected behaviour. Could not convert TeachingTasks to hash.";

## sciences.txt (horaire file) is a true CSV with quoted fields and
## such, so we don't use our CSV_map but the real Text::CSV module.
my $csv = Text::CSV->new( { binary => 1 } )
  and open my $fh_for_horaire, "<:encoding(UTF-8)", $horaire_fn
  or die "Cannot open file: $horaire_fn";

my $fh_for_horaire2;
if ($additionnalschedule_fn) {
  open $fh_for_horaire2, "<:encoding(UTF-8)", $additionnalschedule_fn;
}

## throw header line away
$csv->getline($fh_for_horaire);

while (1) {
  my $row = $csv->getline($fh_for_horaire);
  unless (not $additionnalschedule_fn or $row) {
    $row = $csv->getline($fh_for_horaire2);
  }
  last unless $row;

  my ($name, # mnemonique/NRE|Global/EXM|PED|THE|EXE/Q1|Q2
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
  next if grep { $name =~ $_ } @skipscheduledlines;
  next if $coche eq "Décoché";

  my ($mnemonique, undef,$type,$quadri) = $name =~ m!^([^/]+)/([^/]+)/(EXM|EXE|THE|PED|TPR|PRS)/(..)!
    or MyDebug::suspicious($row,"Cannot parse","$name") && next;

  # skip courses not in our list.
  next unless defined $TeachingTasks->{"$mnemonique"};

  # if (defined $ignorequadriforschedule) {
  #   #$DB::single = 1 if $quadri =~ /$ignorequadriforschedule/;
  #   $DB::single = 1 if $name eq "MATHF101/18395/EXE/Q2";
  # }
  next unless $type =~ /EXE|THE/;

  MyDebug::suspicious($row->[0],"Suspicious value for quadri") && next unless $quadri =~ /Q1|Q2/;
  MyDebug::suspicious($row->[0],"No day given") && next unless $dayofweek;

  my @studentset =
    map {
      s/ *$//; $_
      }
      split /;/, $studentset;
  #  MyDebug::suspicious($row->[0],"No studentset") unless @studentset;

  ## Find good candidates. Le plan est de sélectionner au sein de
  ## repartition.txt les objets qui correspondent à la ligne horaire
  ## actuelle par grep successifs.
  my $candidates;
  push @$candidates, @{$TeachingTasks->{"$mnemonique"}};
  # MyDebug::suspicious($row->[0],"INFO: No candidates for record") and
  next unless @$candidates;
  my $th_or_ex = { "THE" => "th", "EXE" => "ex" }->{$type};
  @$candidates = grep {
    $_->thorex eq $type
      and ($_->modulation->{$th_or_ex} > 0
           or $_->mnemonic eq "INDISPONIBLE");
    ## FIXME: aren't we going to miss special cases ?
  } @$candidates;
  @$candidates = grep {
    if (@studentset and $_->group) {
      ## If the current task has a group and the schedule line also,
      ## they should match unless $_->group explicitly maps to ""
      if (defined $ourgroup2facgroup{$_->group}) {
        $ourgroup2facgroup{$_->group} eq ""
          or $ourgroup2facgroup{$_->group} ~~ @studentset;
      } else {
        $_->group ~~ @studentset;
      }
    } else {
      1;
    }
  } @$candidates;

  @$candidates = grep {
    not $_->quadri ## if there is a quadri, it must match
      or $quadri eq $_->quadri;
  } @$candidates;

  ## FIXME: Check if teacher is eq to the assigned teacher (or at
  ## least a non empty intersection). Only for th.

  MyDebug::suspicious($row->[0],"WARNING: No more candidates for record")
      if scalar @$candidates < 1;

  next if scalar @$candidates < 1;

  $csv->combine(@$row);       ## for debugging purpose.
  my $creneau = CreneauHoraire->new(
                      raw => $csv->string(), ## for debugging purpose.
                      rawweeks=> $weeks,
                      dayofweek => $dayofweek,
                      begin => $beginhour,
                      duration => $duration,
                      auditorium => $auditorium
                     );
  foreach my $associatedtask (@$candidates) {
    $associatedtask->horaire->addCreneau($creneau);
  }
}
close $fh_for_horaire;
close $fh_for_horaire2 if $fh_for_horaire2;


# La lecture est finie, on commence à compter.
# FIXME: ce globalcount ne sert qu'au rapport. Déplacer là bas ?
my $globalcount;
my $globalcount_explicit_tasks;
# $globalcount->{THE EXE}->{BA MA}->{OPT OBLI SE}
{
  foreach my $task (@TeachingTasks) {
    # next unless $teacheropts =~ $task->owner->status; # use $keepteacher ? ## What's the point of skipping these tasks ? They count !
    $globalcount->{$task->thorex}->{$task->course->cycle}->{$task->course->status} +=
      $task->modulation->eq_th;
    $globalcount_explicit_tasks->{$task->thorex}->{$task->course->cycle}->{$task->course->status} .=
      $task->mnemo . "[" . $task->modulation->rawstring . "]" . "\n" if $task->modulation->eq_th();
  }
}

if (0) { ## quelques vérifications
  # Vérifions la compatibilité entre modulation affectée et horaire pour chaque tâche.
  foreach my $task (@TeachingTasks) {
    my $scheduled = $task->horaire->totalhms;
    my $programmed = $task->modulation->totalhms;
    my $diff = $scheduled->absolute - $programmed->absolute;
    if ($diff != 0) {
    printf "%10s %-45s : %s %s\n", $diff, $task->raw,  $task->horaire->totalhms->printHM, $task->modulation->totalhms->printHM;
    }
  }
}
if ($print_tasks_conflicts) {
  foreach my $task (@TeachingTasks) {
    my @conflicts = grep { 
       $task ne $_ and $_->clashp($task);
    } @TeachingTasks;
    if (@conflicts) {
      print $task->raw; # FIXME: we should not use this for other than debugging.
      foreach my $conflicting_course (@conflicts) {
        my @plages_en_conflit = $conflicting_course->clashp($task);
        if (scalar @plages_en_conflit == 1) {
          printf  ("|%s (%s - %s)", # two spaces after 'printf' ensures that no warning is issued
                   $conflicting_course->raw,
                   scalar @{$plages_en_conflit[0]->weeks},
                   $plages_en_conflit[0]->print);
        } elsif (scalar @plages_en_conflit == 2) {
          printf  ("|%s (%s - %s et %s)",
                   $conflicting_course->raw,
                   scalar @{$plages_en_conflit[1]->weeks} + scalar @{$plages_en_conflit[0]->weeks},
                   $plages_en_conflit[0]->print,
                   $plages_en_conflit[1]->print);
        } else {
          printf "|%s (%s)", $conflicting_course->raw, scalar $conflicting_course->clashp($task);
        }
      }
      print "\n";
    }
  }
}
# foreach my $task (@TeachingTasks) {
#   print $task->raw . "\n";
#   print $task->horaire->print() . "\n";
# }
if ($print_teacher_conflicts) {
  foreach my $teacher (@Teachers) {
    print $teacher->printconflicts;
  }
}

if ($print_charges) {
  my @assistants = grep { $_->status eq 1 } @Teachers;
  #FIXME: que faire des intérim mi temps ? Attention aux EA ! utiliser
  #keepteacher ? Il faut alors une moyenne utile pour chaque groupe !
  #Inutile de comparer les assistants aux titulaires.
  my @teachers = grep { keepteacher($_) } @Teachers;
  my $usescorep= ($teacheropts eq "1"); # ugly hack to not try and
                                         # compute score when looking
                                         # at more than just normal
                                         # "assistants temps plein".
                                         # car ça foire dès qu'il y a
                                         # autre chose. Même comme ça
                                         # ça risque de foirer (e.g.
                                         # assistant qui passe au
                                         # fria, etc.)
  if  ($usescorep) {
    @teachers = sort { ($b->score // 0) <=> ($a->score // 0) } @teachers;
  } else {
    @teachers = sort {
      ($a->totalcount($print_quadri || "")->eq_th)
        <=>
        ($b->totalcount($print_quadri || "")->eq_th)
      } @teachers;
  }
  foreach
    my $teacher (@teachers) {
      printf "%-13s %3d %3s\n",
        $teacher->shortname,
        $teacher->totalcount($print_quadri || "")->eq_th ,
        $usescorep ? sprintf "%d", 100*$teacher->meanscore(\@assistants) : "";
    }
}

if ($print_format_xls_fac) {
  ## théorie
  my @rows;
  foreach my $course (sort { $a->mnemonic cmp $b->mnemonic } @Courses) {
    next if $course->mnemonic =~ /^CP/; # coordination péda.

    my $modulation_th = 0;
    my %titulaires;
    my @row;
    foreach my $task (@{$course->tasks}) {
      next unless $task->thorex eq "THE";
      next if $task->owner->shortname =~ m/^(Y|Z|XTP)$/;
      #^ cours gelé, supprimé et TP non attribué.

      $modulation_th = $modulation_th + $task->modulation->th;

      ## We can't put an object as key, so we put shortname and
      ## retrieve the corresponding object later when needed.
      $titulaires{$task->owner->shortname} += $task->modulation->th;
    }

    next unless %titulaires;

    ## Don't count someone if they do nothing !! Unless s/he is alone.
    ## FIXME: perhaps: "unless nobody does anything" ?
    unless (scalar keys %titulaires == 1) {
      foreach my $prof (keys %titulaires) {
        delete $titulaires{$prof} unless $titulaires{$prof};
      }
    }
    push(@row,
         "", ## Course ID ?
         $course->mnemonic,
         $course->name,
         $modulation_th,
         scalar(keys %titulaires),
         "", ## anet list ?
        );
    foreach my $prof (sort keys %titulaires) {
      push(@row,
           find_teacher_by_shortname($prof,\@Teachers)->fullname,
           $titulaires{$prof},
           "" ## anet list for teacher ?
          );
    }
    push(@rows, \@row);
  }
  my $csv = Text::CSV->new ( { binary => 1, eol => "\n" } )  # should set binary attribute.
    or die "Cannot use CSV: ".Text::CSV->error_diag ();

  ## output happens
  open my $output_csv_fh, ">:encoding(utf8)", $output_csv_fn or die "Can't open new CSV file: $!";
  $csv->print ($output_csv_fh, $_) for @rows;

}

if ($print_emails) {
  for my $teacher (@Teachers) {
    if ((keepteacher($teacher)) and (grep { $_->eq_th } $teacher->teachingtasks)) {
      if ($teacher->email) {
        print $teacher->email . "\n";
      } else {
        print STDERR "No mail for ". $teacher->shortname . "\n" if $print_verbose_info;
      }
    }
  }
}
# This is where we write to files.
if ($print_global_report) {
  for (@files) {
    die "Cannot copy to $outdir, file exists: $_\n" if -f "$outdir/$_";
  }
  system("cp","-i", @files, $outdir);
  open(my $skel, "<:encoding(UTF-8)", "$report_skel_fn") or die "Cannot find skeleton for report.";
  open(my $report_fh, ">:encoding(UTF-8)", "$report_fn") or die;
  open(my $gp_data_fh, ">", "$data_fn") or die;
  open(my $gp_plot_fh, ">", "$gnuplot_fn") or die;
  print $gp_data_fh "# data for teaching load, x = (ex + tp) / $Th_Exe_factor, y = th\n";
  printf $gp_plot_fh <<'EOF', $annee_aca, $loadeps_fn;
set xlabel "Exe (h-th)"
set ylabel "Th (h-th)"
set title "Charges d'enseignement %s"
set terminal postscript
set output "%s"
EOF
#   print $gp_plot_fh <<'EOF';
# show label
# plot "$data_fn" using 1:2 with points ps 2 pt 13
# EOF

  print $report_fh "\\newcommand\\facteurThExe{$Th_Exe_factor}\n";
  print $report_fh "\\newcommand\\anneeaca{$annee_aca}\n";

  ## print header
  print $report_fh $_ until not defined ($_ = <$skel>) or m'@@@DATA@@@';
  foreach my $teacher (sort {
    my $A = $a->shortname; my $B = $b->shortname;
    $A = "AAA$A" if $A =~ /^(X|XTP|Y|Z)$/;
    $B = "AAA$B" if $B =~ /^(X|XTP|Y|Z)$/;
    #^ Use AAA for beginning, zzz for end (attention caps!)
    $A cmp $B;
  }
                       grep { $teacheropts =~ $_->status;} #FIXME use $keepteacher
                       @Teachers) {
    print $report_fh $teacher->printreport({ admintasks => $print_admin_tasks,
                                            quadri => $print_quadri,
                                            horaire => $print_horaire });
    print $gp_data_fh $teacher->printgpdata() . "\n";
    print $gp_plot_fh $teacher->printgpplot() . "\n";
  }
  printf $gp_plot_fh 'plot "%s" using 1:2 with points ps 2 pt 13', basename($data_fn);
  ## global counts

  my $hhead = ["BA", "MA"];
  my $vhead = [[ "2" => "de service"], ["1" => "obligatoire"], ["0" => "optionnel"] ];
  print $report_fh "\\section{Tableaux}Les décomptes sont en \\texttt{eq-th}";
  print $report_fh "\\subsection{Théorie}\n\n";
  print $report_fh pretty_print_2D_table($globalcount->{"THE"}, $hhead, $vhead);
  print $report_fh "\\subsection{Exercices}\n\n";
  print $report_fh pretty_print_2D_table($globalcount->{"EXE"}, $hhead, $vhead);

  print $report_fh "\\section{Tableaux explicites}Modulation en th/ex/travaux";
  print $report_fh "\\subsection{Théorie}\n\n";
  print $report_fh pretty_print_2D_table($globalcount_explicit_tasks->{"THE"}, $hhead, $vhead);
  print $report_fh "\\subsection{Exercices}\n\n";
  print $report_fh pretty_print_2D_table($globalcount_explicit_tasks->{"EXE"}, $hhead, $vhead);


  # ## Print list of courses
  # {
  #   print $report_fh "\\section{Liste des collègues}\n";
  #   print $report_fh "Pour les cours où plusieurs personnes interviennent, voici la liste de ces personnes. Toutes les personnes liées au cours donné sont prises en considération, y compris les personnes n'ayant pas de tâches assignées pour l'année académique considérée (par exemple : co-titularisation en alternance).\n";
  #   print $report_fh "\\begin{longtabu}{l>{\\rightskip 0pt plus 1fil}l}\n";
  #   print $report_fh "Cours & Collègues\\\\\n";
  #   foreach my $course (sort { $a->mnemonic cmp $b->mnemonic } @Courses) {
  #     my $line = $course->print();
  #     print $report_fh $line  . "\\\\\n" if $line;
  #   }
  #   print $report_fh "\\end{longtabu}\n";
  # }

  ## Print complete list of courses.
  {
    print $report_fh "\\section{Liste des cours}\nCe qui suit est une liste des tâches associées à chacun des cours. Certains cours sont factices (p.ex. CP = Coordination Pédagogique)\n";
    print $report_fh "\\lightrulewidth=0.1pt\n";
    print $report_fh "\\begin{longtabu}{lllllll}\n";
    print $report_fh "\\toprule Cours & Groupe & Enseignant & Th & Ex & Tp\\\\\\midrule\\midrule\n";
    foreach my $course (sort { $a->mnemonic cmp $b->mnemonic } @Courses) {
      my $line = $course->printcoursereport();
      print $report_fh $line . "\\\\\\midrule\n" if $line;
    }
    print $report_fh "\\end{longtabu}\n";
  }
  ## print footer
  print $report_fh $_ while <$skel>;

  # printf STDERR "DEBUG: The newly generated report and the older one are identical.\n"
  #   if system("diff","-u","$report_fn~","$report_fn") == 0 and $print_verbose_info;
}

if ($print_verbose_info) {
  my $oldfh = select (STDERR);
  foreach (sort keys %MyDebug::suspicious) {
    MyDebug::show_message_and_list($_,@{$MyDebug::suspicious{$_}});
    # print $_ . "\n";
    # do {
    #   s/^/    /mg;
    #   print ;
    # }  for ;
  }
  select ($oldfh);
}

exit(0);
