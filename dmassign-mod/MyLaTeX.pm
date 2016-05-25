## a few latex-related formatting commands

sub format_latex_table_line {
  return join(" & ",
              map {
                $_ = join(", ", split(/\n/));
                $_ // ""; } @_) . "\\\\\n";
}
sub pp_2D_aoa {
  ## Usage: pp_2D_aoa(aref)
  ## Outputs a LaTeX table corresponding to an AoA referenced by AREF.

  ## AREF is a reference to an array of (i) strings (ii) refs to array

  my $aref = shift;
  my $header;
  my $footer;
  my $longestlength = 0;
  my $result = "";

  foreach my $line (@$aref) {
    if (ref ($line) eq 'ARRAY') {
      $result .= format_latex_table_line(@$line);
      if (scalar @$line > $longestlength) {
        $longestlength = scalar @$line;
      }
    }
    else {
      $result .= $line;
    }
  }
  my $factor = 1/$longestlength;
  $header = "\\begin{tabular}{" . "V{$factor\\hsize}" x $longestlength . "}\n";
  $footer = "\\end{tabular}\n";
  return $header . $result . $footer;
}
sub array_ref_to_vertical_table {
  my $aref = shift;
  my @array = map { [ $_ ] } @$aref;
  pp_2D_aoa(\@array);
}
sub pretty_print_2D_table {
  ## We have a hash table of hash tables which we want to pretty print
  ## as a 2D LaTeX table. Return it as a string.

  ## We want to produce :
  ##     y_1 y_2 y_3
  ## x_1
  ## x_2
  ## x_3
  ## where the element at (x_i,y_j) is $href->{x_i}->{y_j}

  ## Usage: pretty_print_2D_table(href, \@x, \@y) - HREF is a
  ##   reference to the hash table you want to print - @x, @y are
  ##   tables of keys containing the x_i's and y_i's respectively (see
  ##   below). Alternatively, an element can be a ref to a pair whose
  ##   first element is the key to use (for lookup in $href), and
  ##   second element is the value to show in the table header.

  my ($href, $x, $y) = @_;
  my @result;

  ## +1 for unreadability. This is to make some sort of sorted
  ## association list: an array of pairs.
  my @x = $x ? @$x : keys %$href; # in case $x wasn't given, compute it
  @x = map { ref $_ ? $_ : [ $_ => $_ ] } @x; # make an alist "key => header"
  return "" if scalar @x == 0; # no x's ?

  ## same game:
  my @y = $y ? @$y : keys %{$href->{$x[0]}}; # in case no $y is given
  @y = map { ref $_ ? $_ : [ $_ => $_ ] } @y; # make an alist "key => header"
  return "" if scalar @y == 0; # no y's ?

  ## create header and push it.
  push @result, [ "" , map { $_->[1] } @y ], "\\hline\n";

  ## push other rows.
  foreach my $x (@x) {
    push @result, [ $x->[1], map { $href->{$x->[0]}->{$_->[0]}; } @y ];
  }

  ## use helper function to print the resulting array as latex table.
  return pp_2D_aoa(\@result);
}

1;
