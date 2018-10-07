package HTTP::Tiny::Cache;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Digest::SHA;
use File::Util::Tempdir;
use JSON::MaybeXS;

use parent 'HTTP::Tiny';

sub request {
    my ($self, $method, $url, $options) = @_;

    unless ($method eq 'GET') {
        log_trace "Not a GET response, skip caching";
        return $self->SUPER::request($method, $url, $options);
    }

    my $tempdir = File::Util::Tempdir::get_user_tempdir();
    my $cachedir = "$tempdir/http_tiny_cache";
    #log_trace "Cache dir is %s", $cachedir;
    unless (-d $cachedir) {
        mkdir $cachedir or die "Can't mkdir '$cachedir': $!";
    }
    my $cachepath = "$cachedir/".Digest::SHA::sha256_hex($url);
    log_trace "Cache file is %s", $cachepath;

    my $maxage =
        $ENV{HTTP_TINY_CACHE_MAX_AGE} //
        $ENV{CACHE_MAX_AGE} // 86400;
    if (!(-f $cachepath) || (-M _) > $maxage/86400) {
        log_trace "Retrieving response from remote ...";
        my $res = $self->SUPER::request($method, $url, $options);
        return $res unless $res->{status} =~ /\A[23]/; # HTTP::Tiny only regards 2xx as success
        log_trace "Saving response to cache ...";
        open my $fh, ">", $cachepath or die "Can't create cache file '$cachepath' for '$url': $!";
        print $fh JSON::MaybeXS::encode_json($res);
        close $fh;
        return $res;
    } else {
        log_trace "Retrieving response from cache ...";
        open my $fh, "<", $cachepath or die "Can't read cache file '$cachepath' for '$url': $!";
        local $/;
        my $res = JSON::MaybeXS::decode_json(scalar <$fh>);
        close $fh;
        return $res;
    }
}

1;
# ABSTRACT: Cache HTTP::Tiny responses

=head1 SYNOPSIS

 use HTTP::Tiny::Cache;

 my $res  = HTTP::Tiny::Cache->new->get("http://www.example.com/");
 my $res2 = HTTP::Tiny::Cache->request(GET => "http://www.example.com/"); # cached response


=head1 DESCRIPTION

This class is a subclass of L<HTTP::Tiny> that cache responses.

Currently only GET requests are cached. Cache are keyed by SHA256-hex(URL).
Error responses are also cached. Currently no cache-related HTTP request or
response headers (e.g. C<Cache-Control>) are respected.

To determine cache max age, this module will consult environment variables (see
L</"ENVIRONMENT">). If all environment variables are not set, will use the
default 86400 (1 day).


=head1 ENVIRONMENT

=head2 CACHE_MAX_AGE

Int. Will be consulted after L</"HTTP_TINY_CACHE_MAX_AGE">.

=head2 HTTP_TINY_CACHE_MAX_AGE

Int. Will be consulted before L</"CACHE_MAX_AGE">.


=head1 SEE ALSO

L<HTTP::Tiny>

L<HTTP::Tiny::Patch::Cache>, patch version of this module.
