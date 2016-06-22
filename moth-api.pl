#!/usr/bin/env perl
use strict; use warnings;

use Dancer2;
use Data::Dumper;

use HTTP::Tiny;
use JSON;
use URI;

# We output JSON for this
set serializer => 'JSON';

# TODO Make these configurable
my $crate_host = 'localhost';
my $crate_port = 4200;

my $base_url = URI->new(
    sprintf("http://%s:%s/_sql", $crate_host, $crate_port),
);

our $json = JSON->new()->utf8(1);

# TODO Pull these out into a separate module
# TODO Refactor querying Crate and getting of data
sub get_streams() { moth_query('moth_streams') }

sub get_stream_sensors($) {
    my ($stream_id) = @_;
    moth_query('moth_sensors', ['stream'], [$stream_id]);
}

sub get_stream($) {
    my ($stream_id) = @_;

    my $stream_data = moth_query_item('moth_streams', ['id'],     [$stream_id]);
    my $sensor_data = moth_query('moth_sensors', ['stream'], [$stream_id]);

    $stream_data->{'sensors'} = $sensor_data;

    return $stream_data;
}

sub get_samples($) {
    my ($stream_id) = @_;

    my $samples = moth_query('moth_samples', ['stream'], [$stream_id]);

    foreach my $sample (@$samples) {
        my $sample_id = $sample->{id};

        my $sample_data =
            moth_query('moth_sample_data', ['sample'], [$sample_id]);

        push @{$sample->{data}}, $sample_data;
    }

    return $samples;
}

sub get_sensors() {
    return moth_query('moth_sensors');
}

sub get_sensor($) {
    my ($sensor_id) = @_;

    my $sensor = moth_query_item('moth_sensors', ['id'], [$sensor_id]);
    my $metadata = moth_query('moth_sensor_metadata', ['sensor'], [$sensor_id]);

    $sensor->{metadata} = [];

    foreach my $row (@$metadata) {
        push @{$sensor->{metadata}}, { key => $row->{k}, value => $row->{v} };
    }

    return $sensor;
}

sub get_sensor_samples($) {
    my ($sensor_id) = @_;

    my $sensor = get_sensor($sensor_id);

    my $samples = moth_query(
        'moth_sample_data',
        ['sensor'],
        [$sensor_id],
        ['inner,moth_samples,moth_samples.id = moth_sample_data.sample'],
    );
    $sensor->{samples} = $samples;

    return $sensor;
}

sub moth_query {
    my ($table, $fields, $params, $joins) = @_;

    $fields //= [];
    $params //= [];
    $joins  //= [];

    my $query = { stmt => "SELECT * FROM $table" };

    foreach my $join (@$joins) {
        my ($type, $table, $clause) = split(/,/, $join);

        die "Bad join spec [$join]" unless ($type && $table && $clause);

        if ($type =~ m/inner/i) {
            $query->{stmt} .=
                sprintf(' INNER JOIN %s ON (%s)', $table, $clause);
        }
        else {
            die "ERROR - BAD JOIN TYPE - Expect 'INNER', got $type ($join)";
        }
    };

    if (scalar @$fields) {
        $query->{stmt} .= sprintf(
            ' WHERE %s',
            join(' AND ', map { $_ =~ /=/ ? $_ : "$_ = ?" } @$fields),
        );
    }

    if (scalar @$params) {
        $query->{args} = $params;
    }

    print Dumper $query;

    my $response = HTTP::Tiny->new()
        ->post($base_url, { content => $json->encode($query)});

    # TODO HTTP Response Code handling
    #print Dumper $response;

    my $content = $json->decode($response->{content});

    my $data = [];

    my $cols = $content->{cols};
    my $rows = $content->{rows};

    foreach my $row (@$rows) {
        my $entry = {};
        @{$entry}{@$cols} = @$row;

        push @{$data}, $entry;
    }

    return $data;
}

sub moth_query_item($;$$$) {
    my $results = moth_query(@_);
    my ($result) = @$results;

    return $result;
}

# Needs a newer version of Dancer2, to support 'send_as HTML => $content'
get '/' => sub {
    my $response = <<HTML;
<html>
    <head>
        <title>Moth API</title>
    </head>
    <body>
        <h1>Moth API</h1>
        <p>This is the Moth API. Use it to store IoT sensor data in streams</p>
    </body>
</html>
HTML
    return $response;
};

get '/streams' => sub {
    get_streams();
};

get '/streams/:stream' => sub {
    get_stream( params->{stream} );
};

get '/streams/:stream/sensors' => sub {
    get_stream_sensors( params->{stream} );
};

get '/streams/:stream/samples' => sub {
    get_samples( params->{stream} );
};

get '/sensors' => sub {
    get_sensors();
};

get '/sensors/:sensor_id' => sub {
    get_sensor(params->{sensor_id});
};

get '/sensors/:sensor_id/samples' => sub {
    get_sensor_samples(params->{sensor_id});
};

dance();
