#!/usr/bin/perl
# blueprintToXML.pl     marc@arthurjames.nl     2012/12/02 12:10:29

use 5.10.0;
use strict;
use warnings;
use open qw/:std :utf8/;
use warnings FATAL => "utf8";

use Data::Dumper;
use XML::LibXML;

### create an alias for %+ for readability
our %MATCH;
*MATCH = \%+;
### paragraph mode
$/ = undef;

$| = 1;

my $commands =
  { DELETE => 'Delete', GET => 'Get', POST => 'Create', PUT => 'Update' };

my $properties_pattern = qr{
    (?<property>      ^\s.*?\n)
}x;

### group pattern
my $group_pattern = qr{
        (?m:^)              (?s:[-]{2}.)
        (?<name>            (\w+))
        (?<group>           [^-]+)
        (?=                 (?: [-]{2}))
}x;

### model pattern
my $model_pattern = qr{
        (?m:^)              (?s:[#]{3}\W+)
        (?<name>            (\w+))
                            \sProperties
        (?=                 [^*]+)
}x;

### property pattern
my $property_pattern = qr{
        (?m:^)              [*]\s
        (?<name>            (\w+))
                            \s\(
        (?<type>            (integer|string))
                            \):\s
        (?<desc>            .+)
}x;

### resource pattern
my $resource_pattern = qr{
        (?m:^)
        ((?<desc>           (?&_desc))\n)?           
        ((?<proto>          (?&_proto))\n)?
        (?<http>            (?&_http))\n
        (>\s(?<inputtype>   (?&_contenttype))\n)?
        ((?<inputparams>    (?&_params))\n)?
        (?<response>        (?&_response))\n
        (<\s(?<outputtype>  (?&_contenttype))\n)?
        ((?<outputlist>     (?&_list)) |
                            (?<output>(?&_params))\n)?

    (?(DEFINE)
        (?<_desc>           [^*\s].+?)
        (?<_proto>          \*\s\`(\w+)\`\s-\s_(optional|required)_\s(.*))
        (?<_http>           (DELETE|GET|POST|PUT)\s(?&_url))
        (?<_url>            (/\w+(/[{}\w]+)?))
        (?<_response>       <\s(\d+))
        (?<_contenttype>    Content-Type:\s([a-z/]+))
        (?<_list>           \[(?&_params)\])
        (?<_params>         {\s(?&_param)(,\s(?&_param))*\s})
        (?<_param>          \"\w+\":(\d+|\"\w+\"))
    )
}x;

sub writeXml {
    my ($endpoints) = @_;
    my $doc = XML::LibXML::Document->new( '1.0', 'utf-8' );
    my $root = $doc->createElement('api');
    foreach my $endpoint (@$endpoints) {
        my $tag = $doc->createElement('endpoint');
        my ( $http, $route ) = split ' ', $endpoint->{http};
        $tag->setAttribute(
            'name' => sprintf '%s %s',
            $commands->{$http}, $route
        );
        $tag->setAttribute( 'group' => '' );
        $tag->setAttribute( 'http'  => $http );

        ### append route
        my $routeElt = $doc->createElement('route');
        $routeElt->appendText($route);
        $tag->appendChild($routeElt);

        ### append description
        if ( defined $endpoint->{desc} ) {
            my $descElt = $doc->createElement('description');
            $descElt->appendText( $endpoint->{desc} );
            $tag->appendChild($descElt);
        }

        ### append parameters
        if ( defined $endpoint->{proto} ) {
            my $parametersElt = $doc->createElement('parameters');
            my $paramElt      = $doc->createElement('parameter');
            $paramElt->setAttribute( 'type' => undef );

            ### parse: '* `first_name` - _optional_ The Person\'s First Name'
            my $name = undef;
            if ( $endpoint->{proto} =~
                /[*]\s`(\w+)`\s-\s\_(optional|required)\_\s(.+)/ )
            {
                $paramElt->setAttribute(
                    'optional' => ( $2 eq 'optional' ? 'true' : 'false' ) );
                $name = $1;
                $paramElt->setAttribute( 'name' => $name );

                ### set description
                my $descElt = $doc->createElement('description');
                $descElt->appendText($3);
                $paramElt->appendChild($descElt);
            }
            ### append example
            if ( defined $endpoint->{inputparams} ) {
                ### parse: '{ "id":2, "first_name":"Bill" }'
                if ( $endpoint->{inputparams} =~ /\"$name\":\"?([^"]+)\"?/ ) {
                    my $exampleElt = $doc->createElement('example');
                    $exampleElt->appendText($1);
                    $paramElt->appendChild($exampleElt);
                }
            }

            ### attach param to parent
            $parametersElt->appendChild($paramElt);
            $tag->appendChild($parametersElt);
        }

        ### append response
        $root->appendChild($tag);
    }
    $doc->setDocumentElement($root);
    print $doc->toString();
}

eval {
    my $file = shift @ARGV;
    open( FILE, $file ) or die "Can't open file: $!\n";
    my $content = <FILE>;
    close FILE;

    ### Parse group definition
    while ( $content =~ /$group_pattern/g ) {
        my $name  = $MATCH{name};
        my $group = $MATCH{group};
        print Dumper $name;
        print Dumper $group;
        print "END CONTENT\n";

        ### Parse model definition
        while ( $group =~ /$model_pattern/g ) {
            my $model = $MATCH{name};
            print Dumper $model;
        }
        print "GROUP $group";
        while ( $group =~ /$property_pattern/g ) {
            print Dumper %MATCH;
        }

    }

    ### Parse resources
    my $endpoints = [];

    while ( $content =~ /$resource_pattern/g ) {
        my $resource = {};
        $resource->{desc}        = $MATCH{desc};
        $resource->{proto}       = $MATCH{proto};
        $resource->{http}        = $MATCH{http};
        $resource->{response}    = $MATCH{response};
        $resource->{inputtype}   = $MATCH{inputtype};
        $resource->{inputparams} = $MATCH{inputparams};
        $resource->{outputtype}  = $MATCH{outputtype};
        $resource->{outputlist}  = $MATCH{outputlist};
        $resource->{output}      = $MATCH{output};

        print Dumper $resource;
        push @$endpoints, $resource;
    }

    writeXml($endpoints);

};
if ($@) {
    print "Error: $@";
}

=head1 NAME

blueprintToXML.pl

=head1 SYNOPSIS



=head1 DESCRIPTION

Stub documentation for blueprintToXML.pl, 
created by template.el.

It looks like the author of this script was negligent 
enough to leave the stub unedited.

=head1 AUTHOR

MJW Lambrichs, E<lt>marc@laptopE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by MJW Lambrichs

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=head1 BUGS

None reported... yet.

=cut
