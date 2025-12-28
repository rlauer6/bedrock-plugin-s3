FROM bedrock-debian

ENV PERL_CPANM_OPT="--mirror-only --mirror https://cpan.openbedrock.net/orepan2 --mirror https://cpan.metacpan.org"

RUN cpanm -v BLM::Startup::S3

# always get the latest version of Bedrock
RUN cpanm -v -n --reinstall Bedrock

RUN DIST_DIR=$(perl -MFile::ShareDir=dist_dir -e 'print dist_dir("BLM-Startup-S3");'); \
     cp $DIST_DIR/s3.xml /var/www/bedrock/config.d/startup

ENTRYPOINT ["/usr/local/bin/start-server"]
