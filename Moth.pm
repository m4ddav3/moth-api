package Moth;
use strict; use warnings;

use HTTP::Tiny;
use JSON;
use URI;

use Data::Dumper;

my $base_url_template = "http://%s:%s/_sql";

my $json = JSON->new()->utf8(1);

sub new {
    my ($class, $host, $port) = @_;

    my $self = {
        host => $host,
        port => $port,
        query_url => undef,
    };

    $self->{query_url} = URI->new(
        sprintf($base_url_template, $host, $port)
    );

    bless $self, ref($class)||$class;

    return $self;
}

# TODO Pull these out into a separate module
# TODO Refactor querying Crate and getting of data
sub get_streams {
    my ($self) = @_;

    return $self->moth_query('moth_streams',
        [qw(id name created_at updated_at)],
        undef, undef, undef,
        ['created_at']);
}

sub get_stream {
    my ($self, $stream_id) = @_;

    my $stream_data = $self->moth_query_item('moth_streams',
        [qw(id name created_at updated_at)],
        ['id'], [$stream_id]);

    $stream_data // die "Stream: $stream_id not found";

    my $sensor_count = $self->moth_query_item('moth_sensors',
        ['COUNT(*) AS val'],
        ['stream'], [$stream_id]);

    my $sample_count = $self->moth_query_item('moth_samples',
        ['COUNT(*) AS val'],
        ['stream'], [$stream_id]);

    $stream_data->{'num_sensors'} = $sensor_count->{val} // 0;
    $stream_data->{'num_samples'} = $sample_count->{val} // 0;

    return $stream_data;
}

sub get_stream_sensors($) {
    my ($self, $stream_id) = @_;

    return $self->moth_query('moth_sensors',
        [qw(id name display_name created_at updated_at)],
        ['stream'], [$stream_id],
        undef,
        ['created_at']);
}

sub get_stream_samples($) {
    my ($self, $stream_id) = @_;

    my $samples = $self->moth_query('moth_samples',
        [qw(id created_at updated_at)],
        ['stream'],
        [$stream_id],
        undef,
        ['created_at']);

    foreach my $sample (@$samples) {
        my $sample_id = $sample->{id};
        $sample->{data} = [];

        my $sample_data = $self->moth_query('moth_sample_data',
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
    my ($self) = @_;

    return $self->moth_query('moth_sensors',
        [qw(id name display_name stream created_at updated_at)]);
}

sub get_sensor($) {
    my ($self, $sensor_id) = @_;

    my $sensor = $self->moth_query_item('moth_sensors',
        [qw(id name display_name stream created_at updated_at)],
        ['id'], [$sensor_id]);

    my $metadata = $self->moth_query('moth_sensor_metadata',
        ['k AS key, v AS value'],
        ['sensor'], [$sensor_id]);

    $sensor->{metadata} = $metadata;

    return $sensor;
}

sub get_sensor_samples($) {
    my ($self, $sensor_id) = @_;

    my $sensor = $self->get_sensor($sensor_id);

    my $samples = $self->moth_query(
        'moth_sample_data',
        [qw(id created_at updated_at)],
        ['sensor'],
        [$sensor_id],
        ['inner,moth_samples,id = moth_sample_data.sample'],
    );
    $sensor->{samples} = $samples;

    return $sensor;
}

sub add_stream ($) {
    my ($self, $stream_data) = @_;

    my $stream_name = $stream_data->{name};
    my $stream_id = $self->moth_next_id('moth_streams');

    $self->moth_insert('moth_streams',
        [qw(id name created_at)],
        [$stream_id, $stream_name, time]);

    return $self->get_stream($stream_id);
}

sub add_stream_sensor ($$) {
    my ($self, $stream_id, $sensor_data) = @_;

    my $stream    = $self->get_stream($stream_id);
    my $sensor_id = $self->moth_next_id('moth_sensors');

    my ($name, $display_name, $metadata) =
        @{$sensor_data}{qw/name display_name metadata/};

    my $created_at = time;

    $self->moth_insert('moth_sensors',
        [qw(id name display_name stream created_at)],
        [$sensor_id, $name, $display_name, $stream_id, $created_at]);

    my $metadata_id = $self->moth_next_id('moth_sensor_metadata');

    my $metadata_entries = [];
    @$metadata_entries = map {
        [ $metadata_id++, $_->{key}, $_->{value}, $sensor_id, $created_at ]
    } @$metadata;

    $self->moth_insert('moth_sensor_metadata',
        [qw(id k v sensor created_at)],
        $metadata_entries);

    return $self->get_sensor($sensor_id);
}

sub add_sample($$) {
    my ($self, $stream_id, $sample_data) = @_;

    # parse the data, insert sample, and sample_data
    # {
    #     created_at: 51401926511601770, (optional)
    #     sensors: [
    #         { <name>, <value> },
    #         ...
    #     ]
    # }

    my $stream_data = $self->get_stream($stream_id);

    my $sample_id = $self->moth_next_id('moth_samples');

    my $created_at = time;

    if (exists $sample_data->{created_at}) {
        $created_at = $sample_data->{created_at};
    }

    $self->moth_insert('moth_samples',
        [qw(id stream created_at)],
        [$sample_id, $stream_id, $created_at]);

    my $sensor_data = $sample_data->{sensors};
    my $sample_data_id = $self->moth_next_id('moth_sample_data');

    my $values = [];

    # Lump all the sensor data into one insert
    foreach my $entry (@$sensor_data) {
        my ($name, $value) = @{$entry}{qw(name value)};

        my $sensor = $self->moth_query_item('moth_sensors',
            ['id'],
            ['name', 'stream'],
            [$name, $stream_id]);

        my $sensor_id = $sensor->{id};

        push @$values, [ $sample_data_id++, $sample_id, $sensor_id, $value ];
    }

    $self->moth_insert('moth_sample_data',
        [qw(id sample sensor value)],
        $values);

    return { sample => $sample_id };
}

sub moth_query ($;$$$$$) {
    my ($self, $table, $fields, $where, $params, $joins, $orders) = @_;

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
        ->post($self->{query_url}, { content => $json->encode($query)});

    # TODO HTTP Response Code handling
    #print Dumper $response;

    my $content = $json->decode($response->{content});

    return moth_response($content);
}

sub moth_query_item ($;$$$$) {
    my ($self, $table, $fields, $where, $params, $joins) = @_;

    my $results = $self->moth_query($table, $fields, $where, $params, $joins);
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
    my ($self, $table) = @_;

    my $result = $self->moth_query_item($table, ['MAX(id) AS last_id']);

    return $result->{last_id} + 1;
}

sub moth_insert ($$$) {
    my ($self, $table, $fields, $values) = @_;

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
        ->post($self->{query_url}, { content => $json->encode($query) });

    # TODO HTTP Response Code handling
    #print Dumper $response;

    my $content = $json->decode($response->{content});

    return moth_response($content);
}

1;
