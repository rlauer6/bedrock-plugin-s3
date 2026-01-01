# README

This is the README that will explain how to test this in a Docker
container.

# Building the Image

Create the tarball and the image by running `make` like this:

```
make clean && make && make image
```

# Running the Container and Testing

## `BLM::Startup::S3`

1. Launch the containers
   ```
   DOCKERIMAGE=s3-plugin DOCKERFILE=Dockerfile docker compose up
   ```

   This will launch a Bedrock enabled web server (Debian version) and
   LocalStack with S3 mocking enabled.
2. Create a bucket and upload a file.
   ```
   aws s3 mb s3://test-bucket --endpoint-url http://localhost:4566 --profile localstack
   aws s3 cp Makefile.am s3://test-bucket/Makefile.am --endpoint-url http://localhost:4566 --profile localstack
   ```
3. Exec into the container:
   ```
   docker exec -it bedrock-plugin-s3-web-1 /bin/bash
   ```
4. Run a test:
   ```
   echo '<trace --output $s3.list_bucket("delimiter", "/")>' | bedrock
   ```
   
## `Apache::BedrockCloudSessionFiles`

Launch the containers and exec into the web container as shown in the
`BLM::Startup::S3` instructions.
