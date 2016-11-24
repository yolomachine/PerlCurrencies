use v5.24;
use HTML::TableExtract;
use LWP::UserAgent;
use HTTP::Request;
use GD::Text;
use GD::Graph;
use GD::Graph::linespoints;
use List::Util qw(min max);
use JSON::Parse 'parse_json';
use Date::Calc;
use Date;

my ($y, $m, $d) = Date::Calc::Today();
my $current_date = Date->new(sprintf '%02d.%02d.%d', $d, $m, $y);

my $help = "
-help                       Show help
		
-s[name(,...)]              Sources to select
                                Available:
                                    cbrf       - Central Bank of Russia
                                    yahoo      - Yahoo finance
                                    wallstreet - Wall Street Journal
                                default: [cbrf,yahoo]
			
-c[name(,...)]              Currencies to select
                                Available:
                                    USD
                                    EUR
                                    GBP
                                    AUD
                                    JPY
                                default: [USD,EUR,GBP,AUD,JPY]

-d[dd.mm.yyyy(,dd.mm.yyyy)] Date range specification
                                One argument:  from first date till today
                                Two arguments: from first date till second
                                default: last 30 days

-sv[value]                  Specify showing of values
                                Available:
                                    true
                                    false
                                default: true, unless date range is 
                                                more than two month
";


my %monitoring_components = (
	sources => [\&yahoo, \&cbrf],
	currency => { from => 'RUB', to => ['USD', 'EUR', 'GBP', 'AUD', 'JPY'] },
	date => { start => $current_date - 30, end => $current_date },
	show_values => 1
);

my %sources = (
	cbrf => \&cbrf,
	yahoo => \&yahoo,
	wallstreet => \&wall_street
);

my %cbrf_currency_codes = (
	USD => 'R01235',
	EUR => 'R01239',
	AUD => 'R01010',
	JPY => 'R01820',
	GBP => 'R01035'
);

my %ws_currency_placement = (
	USD => 43,
	EUR => 37,
	AUD => 14,
	JPY => 19,
	GBP => 48
);

sub draw_graph {
	my @data = @{$_[0]};
	do { map { $_ = (int(($_ * 1000.0) + 0.5) / 1000.0) } @{$_[0]->[$_]} } for 1..@{$_[0]} - 1;
	my $graph = GD::Graph::linespoints->new(max(1280, scalar(@{$_[0]->[0]}) * 20), 720);
	my ($y_max, $y_min) = (0, 10e10);
	for (@data[1..@data - 1]) {
		$y_min = min($y_min, @{$_});
		$y_max = max($y_max, @{$_});
	}
	$y_max += int($y_max) % 2 == 0 ? 2 : 3;
	if (int($y_min) > 3) {
		$y_min -= int($y_min) % 2 == 0 ? 2 : 3
	}
	$graph->set(
		title => $_[2],
      	bgclr => 'black',
      	fgclr => 'white',
      	legendclr => 'white',
      	axislabelclr => 'white',
      	labelclr => 'white',
      	valuesclr => 'white',
      	accentclr => 'white',
      	textclr => 'white',
      	y_label_skip => 2 ,
      	y_label => $monitoring_components{currency}->{from},
      	y_tick_number => int($y_max) - int($y_min),
      	y_max_value => int($y_max),
      	y_min_value => int($y_min),
      	transparent	=> 0,
      	x_labels_vertical => 1,
      	show_values => $monitoring_components{show_values} && (($monitoring_components{date}->{end} - $monitoring_components{date}->{start}) <= 62) ? 1 : 0,
      	marker_size => 2
	) or die $graph->error;
	$graph->set_legend(@{$monitoring_components{currency}->{to}});
	my $file_name = "graph$_[1].png";
	my $plot = $graph->plot($_[0]) // return undef;
	open(IMG, ">$file_name") or die $!;
	binmode IMG;
	print IMG $plot->png;
	say "Saved to $file_name";
}

sub http_request {
	LWP::UserAgent->new->request(HTTP::Request->new( GET => shift ))->decoded_content;
}

sub cbrf {
	my $data = [];
	for (@{$monitoring_components{currency}->{to}}) {
		my $url = "https://www.cbr.ru/currency_base/dynamics.aspx?VAL_NM_RQ=$cbrf_currency_codes{$_}&date_req1=$monitoring_components{date}->{start}&date_req2=$monitoring_components{date}->{end}&rt=1&mode=1";
		my $currency_table = HTML::TableExtract->new(attribs => { class => 'data' })->parse(http_request($url));
		my ($values, $dates, $rows) = ([], [], []);
		push @{$rows}, $_->rows for $currency_table->tables;
		for (@{$rows}[1..@{$rows} - 1]) {
			$_->[2] =~ s/,/./;
			push @{$dates}, $_->[0];
			push @{$values}, $_->[2];
		}
		push @{$data}, $dates if !defined $data->[0];
		push @{$data}, $values;
	}
	draw_graph($data, '_cbrf', 'CBRF');
}

sub wall_street {
	my $data = [];
	my ($dates, $values) = ([], []);
	for (my $i = $monitoring_components{date}->{start}; $i->days <= $monitoring_components{date}->{end}->days; ++$i) {
		$i =~ /(\d+)\.(\d+)\.(\d+)/;
		my $rows = [];
		my $url = "http://online.wsj.com/mdc/public/page/2_3021-forex-$3$2$1.html?mod=mdc_pastcalendar";
		my $currency_table = HTML::TableExtract->new(attribs => { class => 'mdcTable' })->parse(http_request($url));
		next if !$currency_table->tables;
		push @{$dates}, $i;
		push @{$rows}, $_->rows for $currency_table->tables;
		my $usdrub = @{$rows->[$ws_currency_placement{USD}]}[1];
		for (my $j = 0; $j < @{$monitoring_components{currency}->{to}}; ++$j) {
			my $currency = @{$monitoring_components{currency}->{to}}[$j];
			my $val = [];
			if ($currency eq 'USD') {
			    push @{$val}, 1 / $usdrub
			}
			else {
				push @{$val}, ($currency eq 'JPY' ? 100 : 1) * $rows->[$ws_currency_placement{$currency}]->[1] / $usdrub
			}
			if (defined @{$values}[$j]) {
				push @{$values->[$j]}, $val->[0]
			}
			else {
				push @{$values}, $val
			}
		}
	}
	push @{$data}, $dates;
	push @{$data}, $_ for @{$values};
	draw_graph($data, '_wallstreet', 'WALL STREET');
}

sub json_parse {
	my $data = [];
	my $json = parse_json(shift);
	return undef if $json->{error} || !defined $json->{query}->{results};
	my ($values, $dates) = ([], []);
	for (reverse @{$json->{query}->{results}->{quote}}) {
		$_->{Date} =~ s/(\d+)\-(\d+)\-(\d+)/$3\.$2\.$1/;
		push @{$dates}, $_->{Date};
		push @{$values}, $_->{Close};
	}
	push @{$data}, $dates;
	push @{$data}, $values;
    $data;
}

sub yahoo_request_query {
	my ($start, $end, $currency) = @_;
	$start =~ s/(\d+)\.(\d+)\.(\d+)/$3-$2-$1/;
	$end =~ s/(\d+)\.(\d+)\.(\d+)/$3-$2-$1/;
	"https://query.yahooapis.com/v1/public/yql?q=select Date, Close from yahoo.finance.historicaldata where symbol = \"$currency=X\" and startDate = \"$start\" and endDate = \"$end\"&format=json&env=store://datatables.org/alltableswithkeys"
}

sub yahoo {
	my $data = [];	
	my $usdrub = json_parse(
					 http_request(
					     yahoo_request_query(
					     	 $monitoring_components{date}->{start}, 
					     	 $monitoring_components{date}->{end}, 
					     	 $monitoring_components{currency}->{from}
					     	 )
					     )
				 );
	push @{$data}, $usdrub->[0];
	for (@{$monitoring_components{currency}->{to}}) {
		push @{$data}, $usdrub->[1] and next if /USD/;
		my $res = json_parse(http_request(yahoo_request_query($monitoring_components{date}->{start}, $monitoring_components{date}->{end}, $_))) // next;
		my $currency = $_;
		$res->[1]->[$_] = $usdrub->[1]->[$_] * ($currency eq 'JPY' ? 100 : 1) / $res->[1]->[$_] for 0..@{$res->[1]} - 1;
		do { map { $_ = (int(($_ * 1000.0) + 0.5) / 1000.0) } $res->[1]->[$_] } for 0..@{$res->[1]} - 1;
		push @{$data}, $res->[1];
	}
	draw_graph($data, '_yahoo', 'YAHOO FINANCE');
}

for (@ARGV) {
	my $mc = $_;
	if ($mc =~ s/^-s\[(.+)\]/$1/) {
		$monitoring_components{sources} = [];
		push @{$monitoring_components{sources}}, $sources{$_} for split ',', $mc
	}
	elsif ($mc =~ s/^-c\[(.+)\]/$1/) {
		$monitoring_components{currency}->{to} = [split ',', $mc]
	}
	elsif ($mc =~ s/^-d\[(.+)\]/$1/) {
		$mc =~ /(.+),(?:(.+))?/;
		$monitoring_components{date}->{start} = Date->new($1);
		$monitoring_components{date}->{end} = Date->new($2) if defined $2
	}
	elsif ($mc =~ s/^-sv\[(.+)\]/$1/) {
		$monitoring_components{show_values} = 0 if $mc eq 'false'
	}
	elsif ($mc =~ /^-h/) {
		say $help;
		exit;
	}
	else {
		say "Undefined command\n$help";
		exit;
	}
}

do { $monitoring_components{sources}->[$_]->() if defined $monitoring_components{sources}->[$_]  }  for (0..@{$monitoring_components{sources}} - 1);