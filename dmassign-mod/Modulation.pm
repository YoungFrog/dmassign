package Modulation;
use Moose;
use Moose::Util::TypeConstraints;
use HMS;

my $ModulationRegex = qr!^([0-9.]+)/([0-9.]+)/([0-9.]+)$!;
our $Th_Exe_Factor = 2;

has th => ( is => 'rw', isa => 'Num', required => 1 );
has tp => ( is => 'rw', isa => 'Num', required => 1 );
has ex => ( is => 'rw', isa => 'Num', required => 1 );

## FIXME: This can't possibly work correctly, e.g. we can't add
## together things with different Th_Exe_Factor. See add() method for
## further thoughts on this
has ThExeFactor => ( is => 'rw', isa => 'Num', default => $Th_Exe_Factor, lazy => 1 );

around BUILDARGS => sub {
  my $orig  = shift;
  my $class = shift;
  my %hash;
  if (@_ == 1) {
    my $arg = shift;
    if (ref $_[0]) {
      %hash = %$arg;
    } else {
      $hash{rawstring} = $arg;
    }
  } else {
    %hash = @_;
  }
  if (defined($hash{rawstring})) {
    @hash{'th','ex','tp'} = $hash{rawstring} =~ $ModulationRegex
      or die 'Invalid modulation: $hash{rawstring}';
  }
  $class->$orig(%hash);
};

sub eq_th {
  my $object = shift;
  return $object->th + 1/$object->ThExeFactor*($object->ex + $object->tp);
}
sub totalhms {
  my $object = shift;
  return HMS->new(3600*($object->th + $object->ex));
}
sub rawstring {
  my $object = shift;
  return join '/', map { $object->$_ } qw/th ex tp/;
}
sub void {
  my $object = shift;
  return not ($object->th + $object->ex + $object->tp);
}
sub nonvoid {
  return not ((shift)->void());
}
sub add {
  my $object = shift;
  my $object2 = shift;
  $object->$_($object->$_ + $object2->$_) for (qw/th ex tp/);

  ## FIXME: This can't possibly work correctly, e.g. we can't add
  ## together things with different Th_Exe_Factor.
  #if a/b/c factor f is equiv           to a + 1/f (b+c)
  #if a'/b'/c' factor f' is equiv       to a' + 1/f' (b'+c')
  #if a+a'/b+b'/c+c' factor f" is equiv to a+a' + 1/f" (b+b'+c+c')

  #if we want additivity for the eq_th field, we would need
  # f" = (b+b'+c+c')/(1/f' (b'+c') + 1/f (b+c))
  # i.e.
  # $object->ThExeFactor(
  #                      ($object->ex + $object2->ex + $object->tp + $object2->tp)
  #                      /
  #                      (1/$object2->ThExeFactor * ($object2->ex+$object2->tp)
  #                       + 1/$object->ThExeFactor * ($object->ex+$object->tp)));
  1;
}
sub mul {
  my $object = shift;
  my $coef = shift;
  $object->$_($coef * $object->$_) for (qw/th ex tp/);
  return $object;
}

__PACKAGE__->meta->make_immutable;

