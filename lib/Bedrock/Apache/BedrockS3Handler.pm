#
#    This file is a part of Bedrock, a server-side web scripting tool.
#    Copyright (C) 2001, Charles Jones, LLC
#    Copyright (C) 2023, TBC Development Group, LLC
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#

use strict;
use warnings;

use Readonly;

Readonly::Scalar our $BUFFER_SIZE => 4 * 1024;
Readonly::Scalar our $EMPTY       => q{};

Readonly::Scalar our $TRUE  => 1;
Readonly::Scalar our $FALSE => 0;

########################################################################
package S3Config;
########################################################################

use Amazon::Credentials;
use Amazon::S3;
use Carp;

use parent qw(Class::Accessor::Fast);

__PACKAGE__->follow_best_practice;

__PACKAGE__->mk_accessors(qw(s3 host bucket bucket_name));

########################################################################
sub new {
########################################################################
  my ( $class, $options ) = @_;

  my $self = $class->SUPER::new($options);

  my $credentials = eval {
    Amazon::Credentials->new(
      aws_access_key_id     => $options->{AWS_ACCESS_KEY_ID},
      aws_secret_access_key => $options->{AWS_SECRET_ACCESS_KEY},
      token                 => $options->{AWS_SESSION_TOKEN},
      no_passkey_warning    => $FALSE,
      order                 => $options->{order},
    );
  };

  if ( !$credentials ) {
    carp 'no credentials';

    return $FALSE;
  }

  if ( !$self->get_bucket_name ) {
    carp 'no bucket name';
  }

  my $s3 = eval {
    Amazon::S3->new(
      { credentials      => $credentials,
        host             => $self->get_host,
        dns_bucket_names => $self->get_host ? $FALSE : $TRUE,
        secure           => $self->get_host ? $FALSE : $TRUE,
      }
    );
  };

  if ( !$s3 ) {
    carp 'could not instantiate an S3 object';
  }

  $self->set_s3($s3);

  $self->set_bucket( $s3->bucket( $self->get_bucket_name ) );

  return $self;
}

########################################################################
package Bedrock::Apache::BedrockS3Handler;
########################################################################

use Role::Tiny;

use Bedrock::Constants qw(%DEFAULT_MIME_TYPES);
use Bedrock::Apache::Constants qw($OK);
use Carp;
use English qw(-no_match_vars);
use File::Basename qw(fileparse);
use File::Type;

my $host   = $ENV{S3_HOST} // 'https://s3.amazonaws.com';
my $secure = $host =~ /https/xsm ? $TRUE : $FALSE;

$host =~ s/^https?:\/\///xsm;

my $s3_config = S3Config->new(
  { bucket_name           => $ENV{AWS_BUCKET},
    aws_access_key_id     => $ENV{AWS_ACCESS_KEY_ID},
    aws_secret_access_key => $ENV{AWS_SECRET_ACCESS_KEY},
    token                 => $ENV{AWS_SESSION_TOKEN},
    host                  => $host,
    secure                => $secure,
  }
);

########################################################################
sub get_s3_config {
########################################################################
  return $s3_config;
}

########################################################################
sub get_key_from_filename {
########################################################################
  my ( $filename, $session_dir ) = @_;

  my $key = $filename;

  if ( !$session_dir ) {
    $key =~ s/^.*session\///xsm;
  }
  else {
    $key =~ s/^$session_dir\///xsm;
  }

  return $key;
}

########################################################################
sub get_s3_session_file {
########################################################################
  my ( $filename, $session_dir ) = @_;

  my $key = get_key_from_filename( $filename, $session_dir );

  my $bucket = $s3_config->get_bucket;

  my $obj = eval { $bucket->get_key($key); };

  if ( !$obj || $EVAL_ERROR ) {
    carp sprintf 'unable to fetch [%s] from S3: [%s]', $key, $EVAL_ERROR // $EMPTY;
    carp sprintf 'errstr: [%s]', $bucket->errstr // $EMPTY;
  }

  return $obj;
}

########################################################################
sub send_s3_file {
########################################################################
  my ( $r, $filename, $session_dir ) = @_;

  my $obj = get_s3_session_file( $filename, $session_dir );

  die 'not found'
    if !$obj;

  my ( $name, $path, $ext ) = fileparse( $filename, qr/[.][^.]+$/xsm );

  my $mime_type = eval {
    return $DEFAULT_MIME_TYPES{$ext}
      if DEFAULT_MIME_TYPES {$ext};

    return File::Type->new->mime_type( $obj->{value} );
  };

  if ( !$mime_type || $EVAL_ERROR ) {
    $r->log->warn( 'could not determine mime-type ' . $EVAL_ERROR );
    $mime_type = 'application/octet-stream';
  }

  $r->content_type($mime_type);

  $r->send_http_header;

  $r->print( $obj->{value} );

  return $TRUE;
}

########################################################################
sub send_file {
########################################################################
  my ( $r, $filename ) = @_;

  my $buffer;

  ## no critic (RequireBriefOpen)
  my $mime_type = File::Type->new->mime_type($filename);
  $r->content_type($mime_type);

  $r->send_http_header;

  open my $fh, '<', $filename
    or die 'server error';

  while ( read $fh, $buffer, $BUFFER_SIZE ) {
    $r->print($buffer);
  }

  close $fh;

  return $TRUE;
}

1;

## no critic (RequirePodSections)

__END__

=pod

=head1 NAME

Apache::BedrockCloudSessionFiles - serve files from local or S3 session directories

=head1 DESCRIPTION

Implements an Apache handler that serves files from a local session
directory or an S3 session directory.  This is typically used when a
web application wishes to serve a private file to a user, or make a
file available for only a short period of time to a specfic user
session. A typical URI for this type of asset might look like:

 /session/foo.html

In other words, the asset would be protected since the same URL would
not access the asset for anyone other than the requestor since it is
specific to their session.

=head1 NOTES

Use in conjunction with L<BLM::Startup::S3> for best results.

Example:

 <null:session_file '%s/private.pdf'>

Retrieve a file from an S3 bucket...

 <null:pdf $s3.get_key('/private/private.pdf')>

Write the key to the bucket with a prefix of the session

 <null $s3.add_key($session_file.sprintf($session.session), $pdf>

Redirect the client to a URI that will serve the file from S3
 <null $header.see_other('/session/private.pdf')>

=head2 Setting Up the Apache Handler

Setup the handler in your Apache configuration file as shown below:

  Action bedrock-cloudsession-files /cgi-bin/bedrock-session-files.cgi virtual

  Alias /session /var/www/vhosts/mysite/session

  <Directory /var/www/vhosts/mysite/session>
    AcceptPathInfo On
    Options -Indexes
  
    <IfModule mod_perl.c>
      SetHandler perl-script
      PerlHandler Apache::BedrockCloudSessionFiles
      PerlSetEnv AWS_BUCKET mybucket
      PerlSetEnv S3_HOST localstack_main:4566
    </IfModule>
  
    <IfModule !mod_perl.c>
      SetHandler bedrock-session-files
    </IfModule>
  
  </Directory>

If you want to use the CGI version instead of the C<mod_perl> version
of the handler, copy the CGI handler to your F</cgi-bin>
directory. F<bedrock-session-files.cgi> is distributed as part of
Bedrock and can be found at
F</usr/local/lib/bedrock/cgi-bin/bedrock-session-files.cgi>.

=head1 SEE OTHER

L<Bedrock::Handler>, L<Bedrock::Apache::Request_cgi>, L<BLM::Startup::S3>

=head1 AUTHOR

Rob Lauer - <rlauer6@comcast.net>

=cut
