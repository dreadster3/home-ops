import os

STORAGES = {
    "default": {
        "BACKEND": "storages.backends.s3.S3Storage",
        "OPTIONS": {
            "endpoint_url": os.environ.get("AWS_ENDPOINT_URL"),
            "bucket_name": os.environ.get("AWS_BUCKET_NAME"),
            "access_key": os.environ.get("AWS_ACCESS_KEY_ID"),
            "secret_key": os.environ.get("AWS_SECRET_ACCESS_KEY"),
            "location": "media/",
        },
    },
    "scripts": {
        "BACKEND": "storages.backends.s3.S3Storage",
        "OPTIONS": {
            "endpoint_url": os.environ.get("AWS_ENDPOINT_URL"),
            "bucket_name": os.environ.get("AWS_BUCKET_NAME"),
            "access_key": os.environ.get("AWS_ACCESS_KEY_ID"),
            "secret_key": os.environ.get("AWS_SECRET_ACCESS_KEY"),
            "location": "scripts/",
        },
    },
}
