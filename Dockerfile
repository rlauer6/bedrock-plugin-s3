FROM bedrock-debian AS builder

ENV PERL_CPANM_OPT="--mirror-only --mirror https://cpan.openbedrock.net/orepan2 --mirror https://cpan.metacpan.org"

COPY BLM-Startup-S3-*.tar.gz /
RUN apt-get update && apt-get install -y make gcc curl ca-certificates shared-mime-info

########################################################################
# install BLM::Startup::S3 & some optional support files
########################################################################
RUN curl -L https://cpanmin.us | perl - App::cpanminus
RUN cpanm -v -n -l /usr/src/app/local \
    /BLM-Startup-S3*.tar.gz \
    BLM::Startup::SQLiteSession \
    File::Type \
    File::MimeInfo::Magic && \
    rm -rf ~/.cpanm

########################################################################
FROM bedrock-debian
########################################################################
ENV DEBIAN_FRONTEND=noninteractive

COPY --from=builder /usr/src/app/local /usr/src/app/local

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    perl-doc \
    vim \
    less \
    sqlite3 \
    shared-mime-info && \
    rm -rf /var/lib/apt/lists/*

RUN export BLM_STARTUP_S3_DIST_DIR=$(perl -MFile::ShareDir=dist_dir -e 'print dist_dir("BLM-Startup-S3");') && \
    export BEDROCK_DIST_DIR=$(perl -MFile::ShareDir=dist_dir -e 'print dist_dir("Bedrock");') && \
    export BLM_STARTUP_SQLITESESSION_DIST_DIR=$(perl -MFile::ShareDir=dist_dir -e 'print dist_dir("BLM-Startup-SQLiteSession");') && \
    # 1. Setup S3
    cp "$BLM_STARTUP_S3_DIST_DIR/s3.xml" /var/www/bedrock/config.d/startup/ && \
    mkdir -p "$BEDROCK_DIST_DIR/config.d/startup" && \
    cp "$BLM_STARTUP_S3_DIST_DIR/s3.xml" "$BEDROCK_DIST_DIR/config.d/startup/" && \
    # 2. Setup SQLite
    cp "$BLM_STARTUP_SQLITESESSION_DIST_DIR/sqlite.xml" /var/www/bedrock/config.d/startup/ && \
    rm -f /var/www/bedrock/config.d/startup/mysql-session.xml && \
    /usr/src/app/local/bin/bedrock-sqlite.pl -d /var/lib/bedrock/bedrock.db -o www-data

ENV BEDROCK_SESSION_MANAGER='SQLiteSession'
########################################################################

COPY bedrock-cloud-sessions.conf /etc/apache2/conf-available/
RUN a2disconf bedrock-session-files
RUN a2enconf bedrock-cloud-sessions

RUN echo "set mouse-=a" > /root/.vimrc

COPY create-session-file.roc /var/www/html/create-session-file.roc

# setup environment variables for Apache::BedrockCloudSessionFiles
ENV S3_HOST=s3.localhost.localstack.cloud:4566
ENV AWS_BUCKET=test-bucket
ENV AWS_ACCESS_KEY_ID=test
ENV AWS_SECRET_ACCESS_KEY=test

ENV PATH=/usr/src/app/local/bin:$PATH
