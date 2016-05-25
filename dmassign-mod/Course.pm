package Course;
use utf8;
use Moose;
use Moose::Util::TypeConstraints;

has raw => (is => 'ro');
has mnemonic => ( is => 'ro', isa => 'Str' );
has modulation => ( is => 'ro', isa => 'Modulation');
has name => ( is => 'ro', isa => 'Str' );
has coordinateur => ( is => 'rw', isa => 'Teacher' );
has tasks => ( is => 'rw', isa => 'ArrayRef', default => sub { []; }, lazy => 1);
has quadri => ( is => 'rw', isa => maybe_type(enum [ ("", "Q1", "Q2", "Q1+Q2", "??") ]));
has alt => ( is => 'rw', isa => maybe_type(enum [ ("", "1", "2") ]));
has cycle => ( is => 'ro', isa => enum [ qw/BA MA/] );

# 0 = opt, 1 = obligatoire, 2 = service (SE).
enum 'StatusTypes' => [qw(0 1 2)];
has status => ( is => 'ro', isa => 'StatusTypes' );
sub addtask {
  my $object = shift;
  my $task = shift;
  ## If we're adding a task of type "THE", possibly set "coordinateur" field.
  if (not (defined $object->coordinateur) and ($task->thorex eq "THE")) {
    unless ($task->modulation->th) {
      # $DB::single = 1;
      # printf STDERR "Pas coordinateur sans heures de théorie : %s (%s)\n", $task->owner->fullname, $object->mnemonic;
    } else {
      $object->coordinateur($task->owner);
    }
  }

  push @{$object->tasks}, $task;
  return $task;
}
sub print {
  my $object = shift;
  my $result;
  my %collegues;
  foreach my $task (@{$object->tasks}) {
    # $result .= $task->printtasklineforcourse();
    $collegues{$_->owner->fullname} = 1 foreach @{$task->course->tasks};
  }
  #return sprintf "\\begin{tabular}{rllllll}\n\\multicolumn{7}{l}{Cours %s}" . $result . "\\end{tabular}", $object->mnemonic;
  if (keys %collegues > 1) {
    return sprintf "%s & " . join (", ", keys %collegues) . ".", $object->mnemonic;
  } else {
    return;
  }
}; ## cperl didn't see 'print' is a method, not the internal "print".

sub printcoursereport {
  ## Print course in the second part of the report, with one line per task.
  my $object = shift;
  my $result = "";
  my $first = 1;
  foreach my $task (sort { $a->quadri cmp $b->quadri } @{$object->tasks}) {
    my $taskline = $task->printtasklineforcourse({coord => (($object->coordinateur) and (($task->owner) eq ($object->coordinateur)))});
    if ($first) {
      $result .= "\\hypertarget{". $object->mnemonic ."}{" . $object->mnemonic . "}&" . $taskline;
      $first = 0;
    } else {
      $result .= "\\\\\n&" . $taskline;
    }
  }
  return $result ? $result . "\n" : "";
}

__PACKAGE__->meta->make_immutable;
