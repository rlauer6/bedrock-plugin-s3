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

__PACKAGE__->mk_accessors(qw(s3 host bucket bucket_name secure dns_bucket_names));

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
        dns_bucket_names => $self->get_dns_bucket_names,
        secure           => $self->get_secure,
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

use Readonly;
Readonly::Scalar our $DEFAULT_S3_HOST => 'https://s3.amazonaws.com';

{

  my $s3_config;

########################################################################
  sub get_s3_config {
########################################################################
    my ($config) = @_;

    $config //= {};

    return $s3_config
      if $s3_config;

    my $host = $config->{host} // $ENV{S3_HOST} // 'https://s3.amazonaws.com';

    my ($secure) = $host =~ /^http(s)/xsm;

    my $dns_bucket_names      = $config->{dns_bucket_names} // $ENV{S3_HOST} ? $FALSE : $TRUE;
    my $bucket                = $config->{bucket}           // $ENV{AWS_BUCKET};
    my $aws_access_key_id     = $ENV{AWS_ACCESS_KEY_ID}     // $config->{aws_access_key_id};
    my $aws_secret_access_key = $ENV{AWS_SECRET_ACCESS_KEY} // $config->{aws_secret_access_key};
    my $token                 = $ENV{AWS_SESSION_TOKEN};

    $s3_config = S3Config->new(
      { bucket_name           => $bucket,
        aws_access_key_id     => $aws_access_key_id,
        aws_secret_access_key => $aws_secret_access_key,
        token                 => $token,
        host                  => $host,
        secure                => $secure ? $TRUE : $FALSE,
        dns_bucket_names      => $dns_bucket_names,
      }
    );

    return $s3_config;
  }
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

__END__

=pod

=head1 NAME

Apache::Bedrock:S3Handler - serve files from local or S3 session directories

=head1 DESCRIPTION

Role that provides useful methods for implementing S3 based
applications.

=head1 METHODS AND SUBROUTINES

=head2 get_s3_config 

Returns a class that class that implements getters for the S3 client
and bucket objects.

When this class is loaded, the configuration object is initialized
from the environment with these variables:

=over 5

=item S3_HOST

default: https://s3.amazonaws.com

If you provide the name of a host, then DNS bucket names will be
turned off. This is typically done when you using a mocking service
like LocalStack and have not setup domain names for your buckets.

=item AWS_BUCKET (required)

=item AWS_ACCESS_KEY_ID

AWS credential variables are optional. If you are running on an EC2
instance or an ECS container credentials will be retrieved
automatically from the instance metadata.

=item AWS_SECRET_ACCESS_KEY

=item AWS_SESSION_TOKEN

=back

=head3 Methods

=over 5

=item get_s3

Returns an L<Amazon::S3> object.

=item get_bucket_name

Returns the bucket name.

=item get_bucket

Returns a L<Amazon::S3::Bucket> object.

=back

=head2 get_key_from_filename

 get_key_from_filename(filename, [session-dir]);

This poorly names method returns a path to an S3 object, possibly
replacing the 'session' with 'session-dir'. The premise here is that a
request was made for F<session/foo.pdf>. The object was stored under
the user's session directory. That is, 'session' is a virtual
directory that resolves at request time to be the user's session directory.

=head2 get_s3_session_file 

 get_s3_session_file(filename, session-dir)

Retrieves an object from S3 and returns it as a scalar.

=head2 send_s3_file

 send_s3_file(request-handler, filename, session-dir)

Retrieves a file from the S3 bucket that belongs to a particular
session. Attempts to determine the mime type by looking up the
extension in an internal table or by using L<File::Type>.

=head2 send_file 

 send_file(request-handler, filename)

Sends a file to the HTTP client. Attempts to determine the mime type
of the file using L<File::Type>.


=head1 SEE OTHER

L<Bedrock::Handler>, L<Bedrock::Apache::Request_cgi>, L<BLM::Startup::S3>

=head1 AUTHOR

Rob Lauer - <rlauer6@comcast.net>

=cut
