use v5.24;
package Date {
	use List::Util 'reduce';

	use overload 
		'+' => 'addDays',
		'-' => 'subDays',
		'""' => 'toString';

	my @months = qw(0 January February March April May June July August September October November December);
	my @month_days = qw(31 28 31 30 31 30 31 31 30 31 30 31);
	my @weekdays = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);

	my $isLeap = sub {
		my $year = shift;
		$year % 4 == 0 and ($year % 100 != 0 || $year % 400 == 0);
	};

	my $verifyDate = sub {
		my $date = shift;
		my ($day, $month, $year) = ($date->{day}, $date->{month}, $date->{year});
		die "Incorrect year value: $year" if $year < 1;
		die "Incorrect month value: $month" if $month < 1 || $month > 12;
		die "Incorrect day value for $months[$month] in $year : $day" if $day < 1 || $day > $month_days[$month - 1]  + ($month == 2 and $isLeap->($year));
	};

	# https://ru.wikibooks.org/wiki/Реализации_алгоритмов/Вечный_календарь
	my $calculateWeekday = sub {
		my $this = shift;
		my $a = int((14 - $this->{month}) / 12);
  		my $y = $this->{year} - $a;
  		my $m = $this->{month} + 12 * $a - 2;
  		$weekdays[(7000 + ($this->{day} + $y + int($y / 4) - int($y / 100) + int($y / 400) + int((31 * $m) / 12))) % 7];
	};

	# http://alcor.concordia.ca/~gpkatch/gdate-algorithm.html
	my $calculateInDays = sub {
		my $date = shift;
		my ($d, $m, $y) = ($date->{day}, $date->{month}, $date->{year});
		$m = ($m + 9) % 12;
		$y = $y - int($m / 10);
		365 * $y + int($y / 4) - int($y / 100) + int($y / 400) + int(($m * 306 + 5) / 10) + $d - 1;
	};

	# http://alcor.concordia.ca/~gpkatch/gdate-algorithm.html
	my $calculateFromDays = sub {
		my $g = shift;
		my $y = int((10000 * $g + 14780) / 3652425);
		my $ddd = 0;
		$y -= 1 while (($ddd = $g - (365 * $y + int($y / 4) - int($y / 100) + int($y / 400))) < 0);
		my $mi = int((100 * $ddd + 52) / 3060);
		my $mm = ($mi + 2) % 12 + 1;
		$y = $y + int(($mi + 2) / 12);
		my $dd = $ddd - int(($mi * 306 + 5) / 10) + 1;
		my $date = { day => $dd, month => $mm, year => $y };
		return $date;
	};

	my $setDateProp = sub {
		my ($this, $date, $prop, $value) = @_;
		die "Incorrect parameter: \"$value\"" if $value !~ /^[1-9][0-9]*$/;
		$date->{$prop} = $value;
		$this->{date} = $date and $this->{days} = $calculateInDays->($date) if $verifyDate->($date);
	};

	sub INIT {
		no strict 'refs';
		my @props = qw(day month year);
		for my $prop (@props) {
			*$prop = sub {
				my ($this, $value) = @_;
				$setDateProp->($this, $this->{date}, $prop, $value) if defined $value;
				$this->{date}->{$prop};
			}
		}
	}

	sub new {
		my ($class, $value) = @_;
		my $this = { date => undef, days => 0 };
		bless $this, $class;
		die "Passing no arguments" if !defined $value;
		if (ref($value) eq 'Date') {
			$this->{date} = $calculateFromDays->($this->{days} = $value->days);
		}
		elsif (ref(\$value) eq 'SCALAR') {
			if ($value =~ /^[1-9][0-9]*$/) {
				$this->{days} = $value;
				$this->{date} = $calculateFromDays->($value);
			}
			elsif ($value =~ /^(-?\d?\d)\.(-?\d?\d)\.(-?[1-9](\d+)?)/) {
				my $date = { day => $1, month => $2, year => $3 };
				$verifyDate->($date);
				$this->{date} = $date;
				$this->{days} = $calculateInDays->($date);
			}
			else {
				die "Inapropriate format: $value";
			}
		}
		else {
			die "Passing invalid date: $value";
		}
		$this;
	}

	sub weekday {
		my $this = shift;
		$calculateWeekday->($this->{date});
	}

	sub days {
		my $this = shift;
		$calculateInDays->($this->{date});
	}

	sub addDays {
		my ($this, $value) = @_;
		die "Incorrect parameter: \"$value\"" if $value !~ /^-?[1-9][0-9]*$/ || $this->days + $value < 0;
		my $new = new('Date', $this);
		$new->{date} = $calculateFromDays->($this->days + $value);
		$new;
	}

	sub subDays {
		my ($this, $value) = @_;
		return $this->days - $value->days if ref($value) eq 'Date';
		$this->addDays(-$value);
	}

	sub addMonths {
		my ($this, $value) = @_;
		die "Incorrect parameter: \"$value\"" if $value !~ /^-?[1-9][0-9]*$/;
		my $additional_years = int($value < 0 ? ($this->month + $value - 12) / 12 : ($this->month + $value) / 12);
		my $new_month = ($this->month + $value + ($value < 0 ? -1 : 1)) % 12;
		my $date = { day => $this->day, month => $new_month, year => $this->year + $additional_years };
		$this->{date} = $calculateFromDays->($calculateInDays->($date));
		$verifyDate->($this->{date});
		$this;
	}

	sub addYears {
		my ($this, $value) = @_;
		die "Incorrect parameter: \"$value\"" if $value !~ /^-?[1-9][0-9]*$/;
		my $date = { day => $this->day, month => $this->month, year => $this->year + $value };
		$this->{date} = $calculateFromDays->($calculateInDays->($date));
		$verifyDate->($this->{date});
		$this;
	}

	sub toString {
		my $this = shift;
		$this->day . '.' . $this->month . '.' . $this->year;
	}

	sub compare {

	}

	sub isLeap {
		my $this = shift;
		$isLeap->($this->year);
	}

	1;
}