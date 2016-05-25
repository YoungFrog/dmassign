package HMS;
use Moose;
use Moose::Util::TypeConstraints;

has h => ( is => 'rw', isa => subtype as 'Int'# , where { 0 <= $_ and $_ <= 23 }
         );
has m => ( is => 'rw', isa => subtype as 'Int', where { 0 <= $_ and $_ <= 59 } );
has s => ( is => 'rw', isa => subtype as 'Int', where { 0 <= $_ and $_ <= 59 } );

## Can be used as new->(absolute num of seconds) or
## new->(hour:min:seconds) with :seconds being optional.
around BUILDARGS => sub {
  my $orig = shift;
  my $class = shift;
  if ( @_ == 1 && !ref $_[0]) {
    my $raw = shift;
    if ($raw =~ q/^\d+:\d+(:\d+)?$/) {
      my %construct;
      @construct{"h","m","s"} = split ":", $raw;
      $construct{"s"} //= 0;
      return $class->$orig(%construct);
    } elsif ($raw =~ q/^\d+$/) {
      my $result = $class->new(h=>0,m=>0,s=>0);
      $result->absolute($raw);
      return $result;
    } elsif (defined $raw) {
      die "Unparsable HMS string: $raw";
    }
  } else {
    @_ = %{$_[0]} if ref $_[0] eq __PACKAGE__;
    return $class->$orig(@_);
  }
};

sub absolute {
  ## Return time as a number of seconds.
  my $object = shift;
  my $time = shift;
  use integer;
  ## Getter method:
  return 60 * (60 * $object->h + $object->m) + $object->s unless defined $time;

  ## Setter method:
  my ($h,$m,$s);
  $s = $time % 60;
  $time = ($time - $s)/60;
  $m = $time % 60;
  $time = ($time - $m)/60;
  $h = $time;
  $object->h($h);
  $object->m($m);
  $object->s($s);
  return $object->absolute();
}
sub printHM {
  my $object = shift;
  return sprintf "%02d:%02d", $object->h, $object->m;
}
sub printHMS {
  my $object = shift;
  return sprintf '%02d:%02d:%02d', $object->h, $object->m, $object->s;
}
# sub add {
#   my ($obj1, $obj2) = @_;
#   my %res;
#   my $inc = 0;
#   foreach (qw/s m/) {
#     my $summed = $obj1->$_ + $obj2->$_ + $inc;
#     $inc = 0;
#     $summed -= 60 and $inc = 1 if $summed >= 60;
#     $res{$_} = $summed;
#   }
#   $res {h} = $obj1->h + $obj2->h + $inc;
#   return __PACKAGE__->new(%res);
# }
sub add {
  my ($obj1, $obj2) = @_;
  my $result = __PACKAGE__->new(h=>0, m=>0, s=>0);
  $result->absolute($obj1->absolute + $obj2->absolute);
  return $result;
}
sub rem {
  my ($obj1, $obj2) = @_;
  my $result = __PACKAGE__->new(h=>0, m=>0, s=>0);
  die "Unsupported operation: removing too much time will get us yesterday"
    unless $obj1->absolute >= $obj2->absolute;
  $result->absolute($obj1->absolute - $obj2->absolute);
  return $result;
}
no Moose;
__PACKAGE__->meta->make_immutable;
