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
sub get_streams() {
    moth_query('moth_streams', [qw(id name created_at updated_at)]);
}

sub get_stream($) {
    my ($stream_id) = @_;

    my $stream_data = moth_query_item('moth_streams',
        [qw(id name created_at updated_at)],
        ['id'], [$stream_id]);

    $stream_data // die "Stream: $stream_id not found";

    my $sensor_count = moth_query_item('moth_sensors',
        ['COUNT(*) AS val'],
        ['stream'], [$stream_id]);

    my $sample_count = moth_query_item('moth_samples',
        ['COUNT(*) AS val'],
        ['stream'], [$stream_id]);

    $stream_data->{'num_sensors'} = $sensor_count->{val} // 0;
    $stream_data->{'num_samples'} = $sample_count->{val} // 0;

    return $stream_data;
}

sub get_stream_sensors($) {
    my ($stream_id) = @_;
    moth_query('moth_sensors',
        [qw(id name display_name created_at updated_at)],
        ['stream'], [$stream_id]);
}

sub get_stream_samples($) {
    my ($stream_id) = @_;

    my $samples = moth_query('moth_samples',
        [qw(id created_at updated_at)],
        ['stream'],
        [$stream_id],
        undef,
        ['created_at']);

    foreach my $sample (@$samples) {
        my $sample_id = $sample->{id};
        $sample->{data} = [];

        my $sample_data = moth_query('moth_sample_data',
            [qw(id sensor value)],
            ['sample'],
            [$sample_id],
            undef,
            ['id']);

        $sample->{data} = $sample_data;
    }

    return $samples;
}

sub get_sensors() {
    return moth_query('moth_sensors',
        [qw(id name display_name stream created_at updated_at)]);
}

sub get_sensor($) {
    my ($sensor_id) = @_;

    my $sensor = moth_query_item('moth_sensors',
        [qw(id name display_name stream created_at updated_at)],
        ['id'], [$sensor_id]);

    my $metadata = moth_query('moth_sensor_metadata',
        ['k AS key, v AS value'],
        ['sensor'], [$sensor_id]);

    $sensor->{metadata} = $metadata;

    return $sensor;
}

sub get_sensor_samples($) {
    my ($sensor_id) = @_;

    my $sensor = get_sensor($sensor_id);

    my $samples = moth_query(
        'moth_sample_data',
        undef,
        ['sensor'],
        [$sensor_id],
        ['inner,moth_samples,id = moth_sample_data.sample'],
    );
    $sensor->{samples} = $samples;

    return $sensor;
}

sub add_stream ($) {
    my ($stream_data) = @_;

    my $stream_name = $stream_data->{name};
    my $stream_id = moth_next_id('moth_streams');

    moth_insert('moth_streams',
        [qw(id name created_at)],
        [$stream_id, $stream_name, time]);

    return get_stream($stream_id);
}

sub add_stream_sensor ($$) {
    my ($stream_id, $sensor_data) = @_;

    my $stream    = get_stream($stream_id);
    my $sensor_id = moth_next_id('moth_sensors');

    my ($name, $display_name) = @{$sensor_data}{qw/name display_name/};

    moth_insert('moth_sensors',
        [qw(id name display_name stream created_at)],
        [$sensor_id, $name, $display_name, $stream_id, time]);

    return get_sensor($sensor_id);
}

sub add_sample($$) {
    my ($stream_id, $sample_data) = @_;

    # parse the data, insert sample, and sample_data
    # {
    #     created_at: 51401926511601770, (optional)
    #     sensors: [
    #         { <name>, <value> },
    #         ...
    #     ]
    # }

    my $stream_data = get_stream($stream_id);

    my $sample_id = moth_next_id('moth_samples');

    my $created_at = time;

    if (exists $sample_data->{created_at}) {
        $created_at = $sample_data->{created_at};
    }

    moth_insert('moth_samples',
        [qw(id stream created_at)],
        [$sample_id, $stream_id, $created_at]);

    my $sensor_data = $sample_data->{sensors};
    my $sample_data_id = moth_next_id('moth_sample_data');

    my $values = [];

    # Lump all the sensor data into one insert
    foreach my $entry (@$sensor_data) {
        my ($name, $value) = @{$entry}{qw(name value)};

        my $sensor = moth_query_item('moth_sensors',
            ['id'],
            ['name', 'stream'],
            [$name, $stream_id]);

        my $sensor_id = $sensor->{id};

        push @$values, [ $sample_data_id++, $sample_id, $sensor_id, $value ];
    }

    moth_insert('moth_sample_data',
        [qw(id sample sensor value)],
        $values);

    return { sample => $sample_id };
}

sub moth_query ($;$$$$$) {
    my ($table, $fields, $where, $params, $joins, $orders) = @_;

    $fields //= ['*'];
    $where  //= [];
    $params //= [];
    $joins  //= [];
    $orders //= [];

    my $query = {
        stmt => sprintf('SELECT %s FROM %s', join(', ', @$fields), $table),
    };

    foreach my $join (@$joins) {
        my ($type, $table, $clause) = split(/,/, $join);

        die "Bad join spec [$join]" unless ($type && $table && $clause);

        if ($type =~ m/inner/i) {
            $query->{stmt} .=
                sprintf(' INNER JOIN %s ON (%s.%s)', $table, $table, $clause);
        }
        else {
            die "ERROR - BAD JOIN TYPE - Expect 'INNER', got $type ($join)";
        }
    };

    if (scalar @$where) {
        $query->{stmt} .= sprintf(
            ' WHERE %s',
            join(' AND ', map {
                $_ =~ /([=\<\>]| LIKE )/ ? $_ : "$_ = ?";
            } @$where),
        );
    }

    if (scalar @$orders) {
        $query->{stmt} .= sprintf(' ORDER BY %s', join(', ', @$orders));
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

    return moth_response($content);
}

sub moth_query_item ($;$$$$) {
    my ($table, $fields, $where, $params, $joins) = @_;

    my $results = moth_query($table, $fields, $where, $params, $joins);
    my ($result) = @$results;

    return $result;
}

sub moth_response($) {
    my ($content) = @_;

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

sub moth_next_id ($) {
    my ($table) = @_;

    my $result = moth_query_item($table, ['MAX(id) AS last_id']);

    return $result->{last_id} + 1;
}

sub moth_insert ($$$) {
    my ($table, $fields, $values) = @_;

    my $stmt_template = 'INSERT INTO %s (%s) VALUES %s';

    my $values_part = '';

    if (ref $values->[0] eq 'ARRAY') {
        $values_part = join(', ', map {
            sprintf("(%s)", join(', ', map '?', @$fields));
        } @$values);

        my @unrolled_values = map { @$_ } @$values;
        $values = \@unrolled_values;
    }
    else {
        $values_part = sprintf("(%s)", join(', ', map '?', @$fields));
    }

    my $query = {
        stmt => sprintf($stmt_template,
            $table,
            join(', ', @$fields),
            $values_part,
        ),
        args => $values,
    };

    my $response = HTTP::Tiny->new()
        ->post($base_url, { content => $json->encode($query) });

    # TODO HTTP Response Code handling
    #print Dumper $response;

    my $content = $json->decode($response->{content});

    return moth_response($content);
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
    get_stream_samples( params->{stream} );
};

get '/sensors' => sub {
    get_sensors();
};

get '/sensors/:sensor_id' => sub {
    get_sensor( params->{sensor_id} );
};

get '/sensors/:sensor_id/samples' => sub {
    get_sensor_samples( params->{sensor_id} );
};

post '/streams' => sub {
    add_stream( params('body') );
};

post '/streams/:stream/sensors' => sub {
    add_stream_sensor(
        params->{stream},
        params('body'),
    );
};

post '/streams/:stream/samples' => sub {
    add_sample(
        params->{stream},
        params('body'),
    );
};

dance();
