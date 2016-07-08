# moth-api
IoT data API powered by Perl, Dancer2, Crate, Docker, &lt;other buzz words ...>


#### GET /streams

    [
        {
            "id": 1,
            "name": "My Stream",
            "created_at": 123456789,
            "updated_at": null
        },
        ...
    ]

#### GET /streams/:stream

    {
        "id": 1,
        "name": "My Stream",
        "created_at": 123456789,
        "update_at": null,
        "num_sensors": 0,
        "num_samples": 0
    }

#### GET /streams/:stream/sensors

    [
        {
            "id": 1,
            "name": "sensor-1",
            "display_name": "Sensor 1",
            "created_at": 123456789,
            "updated_at": null
        },
        ...
    ],
