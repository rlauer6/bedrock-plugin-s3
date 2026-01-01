#-*- mode: makefile; -*-

PERL_MODULES = \
    lib/BLM/Startup/S3.pm \
    lib/Bedrock/S3.pm \
    lib/Bedrock/Apache/BedrockCloudSessionFiles.pm \
    lib/Bedrock/Apache/BedrockS3Handler.pm

SHELL := /bin/bash

.SHELLFLAGS := -ec

VERSION := $(shell cat VERSION)

%.pm: %.pm.in
	sed  's/[@]PACKAGE_VERSION[@]/$(VERSION)/;' $< > $@

TARBALL = BLM-Startup-S3-$(VERSION).tar.gz

$(TARBALL): buildspec.yml $(PERL_MODULES) requires test-requires README.md
	make-cpan-dist.pl -b $<

README.md: lib/BLM/Startup/S3.pm
	pod2markdown $< > $@

image:
	docker build -f Dockerfile . -t s3-plugin

include version.mk

clean:
	rm -f *.tar.gz $(PERL_MODULES)
