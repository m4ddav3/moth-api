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

#### GET /streams/:stream/samples

    [
        {
            "id": 1,
            "created_at": 1233456789,
            "updated_at": null,
            "data": [
                {
                    "id": 1,
                    "sensor": 1,
                    "value": "<val>"
                },
                ...
            ],
        },
        ...
    ]

#### GET /sensors

    [
        {
            "id": 1,
            "name": "sensor-1",
            "display_name": "Sensor 1",
            "stream": 1,
            "created_at": 123456789,
            "updated_at": null
        },
        ...
    ]

#### GET /sensors/:sensor_id

    {
        "id": 1,
        "name": "sensor-1",
        "display_name": "Sensor 1",
        "stream": 1,
        "created_at": 123456789,
        "updated_at": null,
        "metadata": [
            {
                "key": "Some Key",
                "value": "The Value"
            },
            ...
        ]
    }

#### GET /sensors/:sensor_id/samples

    {
        "id": 1,
        "name": "sensor-1",
        "display_name": "Sensor 1",
        "stream": 1,
        "created_at": 123456789,
        "updated_at": null,
        "metadata": [
            {
                "key": "Some Key",
                "value": "The Value"
            },
            ...
        ],
        "samples": [
            ... TBD ...
        ]
    }
