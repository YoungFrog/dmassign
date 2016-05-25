package AdministrativeTask;
use Moose;
use Moose::Util::TypeConstraints;

has raw => (is => 'ro');
has name => (is => 'ro', isa => 'Str');
has owner => (is => 'ro', isa => 'Teacher');
enum 'LevelTypes' => [qw(* ** *** **** *****)];
has level => ( is => 'ro', isa => 'LevelTypes' );

sub printtaskline {
  my $object = shift;
  my $level = $object->level;
  $level =~ s/\*/\\ast/g;
  return sprintf "%s &\$%s\$\\\\\n", $object->name, $level;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
