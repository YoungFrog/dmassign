package MyDebug;
our %suspicious; ## holds a list of suspicious entries in the horaire file.

## Helper function to aid debugging.
my $dump = sub {
  my $data = shift;
  my $dump;
  if (ref $data eq "ARRAY") {
    my $i = 0;
    $dump .= "$i => $data->[$i]\n" and $i++ while defined($data->[$i]);
  } elsif (ref $data eq "HASH") {
    do {
      $dump .= "$_ => $data->{$_}\n";
    } for (keys %$data);
  } elsif (ref $data eq "") {
    $dump .= $data . "\n";
  } else {
    $DB::single = 2 ;
    die "Cannot dump data $data\n";
  }
  $dump;
};
sub dump {
  $dump->(shift);
}
sub suspicious { ## records these entries
  my $row = shift;
  # $debug and  $DB::single = 2;
  my $message = shift // "Suspicious record";
  my $moreinfo = shift // "";
  my $dumped = $dump->($row);
  $moreinfo =~ s/^\n?//; #make sure there is a leading newline
  $moreinfo =~ s/\n?$/\n/; #make sure there is a trailing newline
  push @{$suspicious{$message}}, "At line $. : " . $moreinfo . $dumped;
};

sub show_message_and_list {
  local $\="\n"; my $oldfh = select (STDERR);
  print scalar shift;
  print "    $_" while defined($_=shift);
  select($oldfh);
}
