package Apache::BedrockCloudSessionFiles;

#
#    This file is a part of Bedrock, a server-side web scripting tool.
#    Copyright (C) 2001, Charles Jones, LLC
#    Copyright (C) 2024, TBC Development Group, LLC
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

use English qw(-no_match_var);
use Bedrock::Apache::Constants qw($OK);
use Data::Dumper;
use File::Type;

use Role::Tiny::With;
with 'Bedrock::Apache::BedrockS3Handler';
with 'Bedrock::Apache::HandlerUtils';

use Readonly;

Readonly::Scalar our $TRUE  => 1;
Readonly::Scalar our $FALSE => 0;

our $VERSION = '1.0.0';

########################################################################
sub handler {
########################################################################
  my ($r) = @_;

  my $s3_config = get_s3_config();

  if ( $s3_config->get_s3 && $s3_config->get_bucket ) {
    $r->log->debug( sprintf 'S3 session files configured for BUCKET [%s]', $s3_config->get_bucket_name );
  }

  # note that get_file_info() validates session and throws exception
  # if file does not exist. turn file checking off so that we can also
  # look in S3 for the session file
  my $file_info = eval { return get_file_info( $r, $FALSE ); };

  return set_error_status( $r, $EVAL_ERROR )
    if !$file_info || $EVAL_ERROR;

  my $filename = $file_info->{filename};

  my $status = eval {
    if ( -e $filename ) {
      $r->log->debug( sprintf 'attempting to read file [%s]', $filename );

      return send_file( $r, $filename );
    }

    die "not found\n"
      if !$s3_config->get_s3 || !$s3_config->get_bucket;

    $r->log->debug( sprintf 'attempting to read key [%s] from S3', $filename );

    return send_s3_file( $r, $filename );
  };

  if ( !$status || $EVAL_ERROR ) {
    if ( $EVAL_ERROR =~ /not\sfound/xsm ) {
      $status = set_error_status( $r, 'not found' );
    }
    else {
      $status = set_error_status( $r, 'server error' );
    }
  }

  return $OK;
}

1;

## no critic (RequirePodSections)

__END__

=pod

=head1 NAME

Apache::BedrockCloudSessionFiles - serve files from local file system or S3

=head1 DESCRIPTION

Implements an Apache handler that serves files from a local session
directory or an S3 bucket.  This is typically used when a
web application wishes to serve a private file to a user, or make a
file available for only a short period of time to a specific user
session.  A typical URI for this type of asset might look like:

 /session/foo.pdf

In other words, the asset would be protected since the same URL would
not access the asset for anyone other than the requestor since it is
specific to their session. Sessions are identified using a session cookie.

=head1 NOTES

Use in conjunction with L<BLM::Startup::S3> for best results ;-)

Example:

Read a PDF from S3 and write to the current user's cloud session
directory.

 <!-- read a file from somewher -->
 <null:pdf $s3.get_key('/private/private.pdf')>

 <!-- write file to user's cloud session directory -->
 <null:session_file '%s/private.pdf'>

 <null $s3.add_key($session_file.sprintf($session.session), $pdf>

 <!-- redirect the to the session file -->
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
      PerlSetEmv S3_HOST localstack_main:4566
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

L<Bedrock::Handler>, L<Bedrock::Apache::Request_cgi>, L<Amazon::S3>

=head1 AUTHOR

Rob Lauer - <bigfoot@cpan.org>

=cut
