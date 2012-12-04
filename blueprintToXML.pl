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
    my ( $endpoints, $models ) = @_;
    my $doc = XML::LibXML::Document->new( '1.0', 'utf-8' );
    $doc->setStandalone(1);
    my $root = $doc->createElementNS( 'http://mashape.com', 'api' );
    $doc->setDocumentElement($root);
    $root->setNamespace( 'http://www.w3.org/2001/XMLSchema-instance', 'xsi',
        0 );
    $root->setAttributeNS(
        'http://www.w3.org/2001/XMLSchema-instance',
        'schemaLocation',
        'http://mashape.com http://www.mashape.com/schema/mashape-4.0.xsd'
    );
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
        ### we need to find the most appropriate model definition
        if ( defined $endpoint->{output} ) {
            ### first, convert output example to a perl hash
            $endpoint->{output} =~ s/:/ => /g;
            my $object = eval $endpoint->{output};
            my $found  = 0;
            foreach my $type ( keys %$models ) {
                my $model = $models->{$type};

                if ( hasSameType( $model, $object ) ) {
                    my $responseElt = $doc->createElement('response');
                    $responseElt->setAttribute( 'type' => $type );
                    $tag->appendChild($responseElt);
                }

            }

        }
        $root->appendChild($tag);
    }
    $doc->setDocumentElement($root);
    print $doc->toString();
}

sub hasSameType() {
    my ( $attrArray, $object ) = @_;
    1;
}

eval {
    my $file = shift @ARGV;
    open( FILE, $file ) or die "Can't open file: $!\n";
    my $content = <FILE>;
    close FILE;

    ### Parse group definition
    my $models = {};
    while ( $content =~ /$group_pattern/g ) {
        my $name  = $MATCH{name};
        my $group = $MATCH{group};
        print Dumper $name;
        print Dumper $group;
        print "END CONTENT\n";

        my $modelname = undef;
        ### Parse model definition
        while ( $group =~ /$model_pattern/g ) {
            $modelname = $MATCH{name};
        }
        print "GROUP $group";

        while ( $group =~ /$property_pattern/g ) {
            my $attribute = {};
            foreach my $key ( keys %MATCH ) {
                $attribute->{$key} = $MATCH{$key};
            }
            if ( defined $models->{$modelname} ) {
                push @{ $models->{$modelname} }, $attribute;
            }
            else {
                $models->{$modelname} = [$attribute];
            }
        }
        print Dumper $models;

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

    writeXml( $endpoints, $models );

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
