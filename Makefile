#-*- mode: makefile; -*-

PERL_MODULES = \
    lib/BLM/Startup/S3.pm \
    lib/Bedrock/Apache/BedrockCloudSessionFiles.pm \
    lib/Bedrock/Apache/BedrockS3Handler.pm

VERSION := $(shell perl -I lib -MBLM::Startup::S3 -e 'print $$BLM::Startup::S3::VERSION;')

TARBALL = BLM-Startup-S3-$(VERSION).tar.gz

$(TARBALL): buildspec.yml $(PERL_MODULES) requires test-requires README.md
	make-cpan-dist.pl -b $<

README.md: lib/BLM/Startup/S3.pm
	pod2markdown $< > $@

clean:
	rm -f *.tar.gz
