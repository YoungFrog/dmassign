package TeachingTask;
use Moose;
use Moose::Util::TypeConstraints;

has todo => (is => 'ro', isa => 'Bool', lazy => 1, default => 0);
has raw => (is => 'ro');
has course => (is => 'ro', isa => 'Course', handles => { "mnemo" => "mnemonic", "name" => "name", "mnemonic" => "mnemonic" });
has quadri => (is => 'ro', isa => enum ([qw/0 Q1 Q2/]));
has owner => (is => 'ro', isa => 'Teacher');
has thorex => ( is => 'ro', isa => enum([qw/THE EXE/]) );
has group => ( is => 'ro', isa => 'Str' );
has modulation => ( is => 'ro',
                    isa => 'Modulation',
                    handles => { map { $_ => $_ } (qw/th tp ex eq_th void/)} );
has horaire => ( is => 'rw',
                 isa => 'Horaire',
                 default => sub { Horaire->new(); },
                 lazy => 1);

## Compare les Horaire des deux TeachingTask (l'objet et l'argument)
sub clashp {
  return $_[0]->horaire->clashp($_[1]->horaire);
}

sub quadri_compute {
  my $object = shift;
  my $quadri_horaire = $object->horaire->quadri("Don't warn");
  my $quadri_assumed = $object->quadri;
  if ($quadri_horaire
      and $quadri_assumed
      and not $quadri_assumed eq $quadri_horaire) {
    print STDERR "Scheduled and assumed quadri do not match for object $object->raw";
  }
  $quadri_horaire || $quadri_assumed;
}

sub printtaskline {
  my $object = shift;
  my $options = shift; # add option for stripping ?
  my $shortmnemo = $object->course->mnemonic;
  # $shortmnemo =~ s/^(MATH|STAT)// # strip prefix. Perhaps add: if $options->{"stripprefix"}; ?
  my $quadri = $object->quadri_compute();
  my $programmedsched = $options->{horaire} ? $object->horaire->totalhms->printHM : "";
  $quadri = $quadri ? "/$quadri" : "";
  return sprintf "\\hyperlink{%s}{%s} -- %s %s &%s &%s &%s &%s& %s h-th & %s\\\\\n",
    $object->course->mnemonic,
    $shortmnemo,
    $object->name,
    $options->{"coord"} ? "(coord.)":"",
    $object->group . $quadri,
    $object->th || "",
    $object->ex || "",
    $object->tp || "",
    $object->eq_th,
    $programmedsched;
}

sub printtasklineforcourse { #FIXME: move to Course.pm ?
  my $object = shift;
  my $options = shift;
  my $group = $object->group || "(Tous)";
  my $quadri = $object->quadri ? $object->quadri . "/" : "";
  return sprintf "%s & \\hyperlink{%s}{%s} %s &%s & %s & %s",
    $quadri . $group,
    $object->owner->shortname,
    $object->owner->fullname,
    $options->{"coord"} ? "(coord.)":"",
    $object->th,
    $object->ex,
    $object->tp;
}
sub almostraw { ## DEBUG ?
  my $object = shift;
  my $raw = $object->raw;
  $raw =~ s/;[^;]*\n?$//;
  return $raw;
}
__PACKAGE__->meta->make_immutable;
