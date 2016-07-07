#!/usr/bin/env perl
use strict; use warnings;

use Dancer2;
use Data::Dumper;

use Moth;

# We output JSON for this
set serializer => 'JSON';

# TODO Make these configurable
my $crate_host = 'localhost';
my $crate_port = 4200;

my $moth = Moth->new($crate_host, $create_port);

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
    $moth->get_streams();
};

get '/streams/:stream' => sub {
    $moth->get_stream( params->{stream} );
};

get '/streams/:stream/sensors' => sub {
    $moth->get_stream_sensors( params->{stream} );
};

get '/streams/:stream/samples' => sub {
    $moth->get_stream_samples( params->{stream} );
};

get '/sensors' => sub {
    $moth->get_sensors();
};

get '/sensors/:sensor_id' => sub {
    $moth->get_sensor( params->{sensor_id} );
};

get '/sensors/:sensor_id/samples' => sub {
    $moth->get_sensor_samples( params->{sensor_id} );
};

post '/streams' => sub {
    $moth->add_stream( params('body') );
};

post '/streams/:stream/sensors' => sub {
    $moth->add_stream_sensor(
        params->{stream},
        params('body'),
    );
};

post '/streams/:stream/samples' => sub {
    $moth->add_sample(
        params->{stream},
        params('body'),
    );
};

dance();
