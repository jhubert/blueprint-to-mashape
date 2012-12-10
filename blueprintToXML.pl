#!/usr/bin/perl
# blueprintToXML.pl     marc@arthurjames.nl     2012/12/02 12:10:29

use 5.10.0;
use strict;
use warnings;

package com::mashape;

use Data::Dumper;
use XML::LibXML;

my $commands =
  { DELETE => 'Delete', GET => 'Get', POST => 'Create', PUT => 'Update' };

sub writeXml {
    my ( $endpoints, $models ) = @_;
    print "writeXml() start\n" if $main::DEBUG;

    ### create xml document
    my $doc = XML::LibXML::Document->new( '1.0', 'utf-8' );
    $doc->setStandalone(1);

    ### set namespaces
    my $root = $doc->createElementNS( 'http://mashape.com', 'api' );
    $doc->setDocumentElement($root);
    $root->setNamespace( 'http://www.w3.org/2001/XMLSchema-instance', 'xsi',
        0 );
    $root->setAttributeNS(
        'http://www.w3.org/2001/XMLSchema-instance',
        'schemaLocation',
        'http://mashape.com http://www.mashape.com/schema/mashape-4.0.xsd'
    );
    ### For all groups
    foreach my $group ( keys %$endpoints ) {
        ### For all endpoints within this group
        foreach my $endpoint ( @{ $endpoints->{$group} } ) {
            ### add endpoint
            my $tag = createEndpoint( $doc, $group, $endpoint, $models );
            $root->appendChild($tag);
        }
    }
    ### add models
    foreach my $model (@$models) {
        my $tag = createModel( $doc, $model );
        $root->appendChild($tag);
    }

    $doc->setDocumentElement($root);
    print $doc->toString(2);
}

sub createModel {
    my ( $doc, $model ) = @_;
    printf "createModel(): start\n" if $main::DEBUG;
    my $modelElt = $doc->createElement('model');
    $modelElt->setAttribute( 'name', $model->{name} );

    if ( ref $model eq 'HASH' ) {
        my $fieldsElt = $doc->createElement('fields');
        foreach my $property ( keys %{ $model->{properties} } ) {
            my $simple = $doc->createElement('simple');
            $simple->setAttribute( 'name', $property );
            $simple->setAttribute( 'type',
                $model->{properties}->{$property}->{type} );
            $fieldsElt->appendChild($simple);
        }
        $modelElt->appendChild($fieldsElt);
    }
    return $modelElt;
}

sub createEndpoint {
    my ( $doc, $group, $endpoint, $models ) = @_;
    printf "createEndpoint(%s): start\n", $endpoint->{resource} if $main::DEBUG;

    my $tag = $doc->createElement('endpoint');
    my ( $http, $route ) = split ' ', $endpoint->{resource};
    ### set attribute 'name' - required
    $tag->setAttribute(
        'name' => sprintf '%s %s',
        $commands->{$http}, $route
    );
    ### set attribute 'group' - optional
    $tag->setAttribute( 'group' => $group );

    ### set attribute 'http' - required (values e {GET, POST, PUT, DELETE})
    $tag->setAttribute( 'http' => $http );

    ### append route
    my $routeElt = $doc->createElement('route');
    my $cdata    = $doc->createCDATASection($route);
    $routeElt->appendChild($cdata);
    $tag->appendChild($routeElt);

    ### append description node
    if ( defined $endpoint->{desc} ) {
        my $descElt = $doc->createElement('description');
        $cdata = $doc->createCDATASection( $endpoint->{desc} );
        $descElt->appendChild($cdata);
        $tag->appendChild($descElt);
    }

    ### append response node
    ### attribute 'type' is an element of {'String', 'Binary', 'ModelName', 'List[ModelName]'
    if ( scalar @{ $endpoint->{actions} } > 0 ) {
        my $responseElt = $doc->createElement('response');
        ### set attribute 'code'. SEE README
        ### TODO what status code? There can me more than one!
        if ( scalar @{ $endpoint->{actions} } == 1 ) {
            my $action = $endpoint->{actions}->[0];
            $responseElt->setAttribute( 'code', $action->{http_status_code} );
            ### set attribute 'type'.
            my $type = _getAppropriateType(
                $models,
                $action->{response_header},
                $action->{response_body}
            );
            $responseElt->setAttribute( 'type', $type ) if defined $type;
            $tag->appendChild($responseElt);
        }

    }

    ### append parameters node
    ### From the documentation:
    ### "If the endpoint has parameters or dynamic URL parameters (placeholders) in
    ###  the route, then those parameters must be defined within this collection"
    if ( exists $endpoint->{params}
        || _hasPlaceholders( $endpoint->{resource} ) )
    {
        my $parameters = createParameters( $doc, $endpoint, $models );
        $tag->appendChild($parameters);
    }
    return $tag;

}

sub _getAppropriateType {
    my ( $models, $header, $body ) = @_;
    print "_getAppropriateType(): start\n" if $main::DEBUG;
    printf "header = %s\n", $header if ( $main::DEBUG && defined $header );
    printf "body = %s\n",   $body   if ( $main::DEBUG && defined $body );

    my $type = undef;
    if ( defined $body ) {
        ### content-type is javascript
        if ( defined $header
            && $header eq 'Content-Type: text/javascript' )
        {
            $type = 'Binary';
        }
        ### TODO content-type is x-www-form-urlencoded
        ### content-type is json
        elsif ( defined $header
            && $header eq 'Content-Type: application/json' )
        {
            ### is it a list?
            if ( $body =~ m/^\[([^]]+)\]$/ ) {
                $type = _determineModel( $1, $models );
                $type = sprintf 'List[%s]', $type
                  if defined $type;
            }
            ### is it an object?
            elsif ( $body =~ /^(\{[^}]+\})$/ ) {
                $type = _determineModel( $1, $models );
            }

        }
    }
    printf "_getAppropriateType(): return %s\n",
      ( defined $type ? $type : 'undef' )
      if $main::DEBUG;
    return $type;
}

sub _determineModel {
    my ( $body, $models ) = @_;
    print "_determineModel(): start\n", Dumper $body if $main::DEBUG;
    my @attributes =
      ref $body eq 'ARRAY' ? @$body : ( $body =~ m/\"(\w+)\":/g );
    my $object = undef;
    foreach my $model (@$models) {
        ### Try to find the model with all attributes
        my %properties = map { $_ => 0 } keys %{ $model->{properties} };
        my $sum = 0;
        $sum += $_ for ( map { exists $properties{$_} ? 1 : 0 } @attributes );

        if ( $sum == scalar keys %properties ) {
            $object = $model->{name};
            last;
        }
    }
    return $object;
}

sub _hasPlaceholders() {
    my $resource = shift;
    return $resource =~ /{\w+}/;
}

sub createParameters {
    my ( $doc, $endpoint, $models ) = @_;
    print "createParameters(): start\n" if $main::DEBUG;

    my $tag = $doc->createElement('parameters');
    ### find correct model:
    ### All params should be defined as property in model
    my $model = _getAppropriateType( $models, $endpoint->{req_header},
        $endpoint->{params} );
    print "213: model = \n", ( defined $model ? $model : '' ) if $main::DEBUG;
    ### check parameters
    if ( exists $endpoint->{params} ) {
        print "214: ", Dumper $endpoint->{params} if $main::DEBUG;
        my %params =
          ( $endpoint->{params} =~ m/\"([^"]+?)\":\s?(\"?[^"},]+\"?)/g );

        foreach my $param ( keys %params ) {
            ### get properties from model
            my $property = undef;
            if ( defined $model ) {
                $property = $model->{properties}->{$param};
                print "property = ", Dumper $property if $main::DEBUG;
            }
            ### if there is no model - and subsequently no property, guess the type
            if ( !defined $property ) {
                $property = _guessType( $param, $params{$param}, $models );
                printf "property = %s\n", $property if $main::DEBUG;
            }
            my $paramElt =
              createParam( $doc, $param, $endpoint->{signatures}, $property );
            $tag->appendChild($paramElt);
        }
    }

    ### check placeholders
    my @placeholders = ( $endpoint->{resource} =~ m/{([^}]+)}/g );

    foreach my $placeholder (@placeholders) {
        my $property = undef;
        ### if there is no model - and subsequently no property, guess the type
        if ( !defined $property ) {
            $property = _guessType( $placeholder, undef, $models );
            printf "property = %s\n", $property if $main::DEBUG;
        }
        my $paramElt =
          createParam( $doc, $placeholder, $endpoint->{signatures}, $property );
        $tag->appendChild($paramElt);
    }

    return $tag;
}

sub _guessType {
    my ( $param, $value, $models ) = @_;
    printf "_guessType(%s, %s): start\n", $param,
      ( defined $value ? $value : 'undef' )
      if $main::DEBUG;

    foreach my $model (@$models) {
        my $properties = $model->{properties};
        foreach my $key ( keys %$properties ) {
            if ( $key eq $param ) {
                return $properties->{$key}->{type};
            }
        }
    }
    if ( defined $value && $value =~ /^\"[^"]+\"$/ ) {
        return 'string';
    }
    elsif ( defined $value && $value =~ /^\d+$/ ) {
        return 'integer';
    }
    else {
        return undef;
    }
}

sub createParam {
    my ( $doc, $param, $signatures, $property ) = @_;
    printf "createParam(%s)\n", $param if $main::DEBUG;

    ### create parameter node
    my $paramElt = $doc->createElement('parameter');
    $paramElt->setAttribute( 'name' => $param );
    $paramElt->setAttribute(
        'type' => ref $property ? $property->{type} : $property );

    ### get corresponding signature
    my $signature = undef;
    if ( defined $signatures ) {
        foreach my $elt (@$signatures) {
            if ( $elt->{name} eq $param ) {
                $signature = $elt;
                last;
            }
        }
    }
    ### Add optionality
    if ( exists $signature->{optional} && $signature->{optional} ) {
        $paramElt->setAttribute( 'optional' => 'true' );
    }
    else {
        $paramElt->setAttribute( 'optional' => 'false' );
    }

    ### Add description
    my $desc =
      exists $signature->{desc} ? $signature->{desc}
      : (
        ref $property && exists $property->{desc} ? $property->{desc}
        : undef
      );
    if ( defined $desc ) {
        my $descElt = $doc->createElement('description');
        my $cdata   = $doc->createCDATASection($desc);
        $descElt->appendChild($cdata);
        $paramElt->appendChild($descElt);
    }

    return $paramElt;
}

1;

package io::apiary;

### section pattern
my $section_pattern = qr{
        (?m)                (^[-]{2}(\s|\n))    # Start '--' followed by space or newline
        (?<name>            (\w[^\n]+))         # name, followed by
                            ((\n                # newline with
        (?<short_desc>      ([^\n]+))\n)        # description
                            |                   # or
                            \s)                 # space
        (?s)                                    # enable reading . as newline
        (?<long_desc>       (.*?))
                            [-]{2}              # end of section
                            \n+
        (?<resources>       (.*?))
        (?=                 (?: ([-]{2}|\z)))   # until lookahead: '--' 
        (?-s)                                   # disable reading . as newline
}x;

### model pattern
my $model_pattern = qr{
        (?m)                ([#]{3}\W+)
        (?<name>            (\w+))
                            \sProperties
        (?s)
        (?<tail>            .*?)
        (?=                 ([#]{3}|\Z))
        (?-s)
}x;

### property pattern
my $property_pattern = qr{
        (?m)                ^\*\s
        (?<name>            \w+)
                            \s\(
        (?<type>            (boolean|datetime|integer|string|uri))
                            \):\s
        (?<desc>            [^\n]+)
}x;

### signature pattern
my $signature_pattern = qr{
        (?m)                ^\*\s\`
        (?<name>            \w+)
                            \`\s-\s
                            (_
        (?<required>        (optional|required))
                            _\s)?
        (?<desc>            [^\n]+)
}x;

### resource pattern
my $resource_pattern = qr{
        (?m)                     (([-]{2})?\n{2,})?


        (?<desc>                 (?&_desc))?                    # description - optional

        (?<signatures>           ((?&_signature)\n)*)           # signatures - optional

        (?<resource>             (?&_resource))                 # resource - required
                                 \n                        
        ((>\s(?<req_header>      (?&_header))                   # request header - optional
                                 \n))?
        ((?<params>              ([^<>]+?))\n)?                 # params - optional

        (?s)                                                    # reading . as newline     
        (?<actions>              (<\s(?&_http_status_code).*?)) # catch multiple actions on a single source
        (?=                      (?: (\n{2,}|\Z)))
        (?-s)                                                   # disable reading . as newline

    (?(DEFINE)
        (?<_desc>                (?s)(.*?)(?<![^\n])(?=((?&_signature)|(?&_resource)))(?-s))
        (?<_signature>           \*\s\`(\w+)\`\s-(\s_(optional|required)_)?\s([^\n]+))
        (?<_resource>            (DELETE|GET|POST|PUT)\s(?&_url))
        (?<_url>                 (/[-\w]+(/[-=?{}\w]*)*))
        (?<_http_status_code>    (\d+))
        (?<_header>              (Accept|Content-Type):\s([-a-z/]+))
    )
}x;

### action pattern
my $action_pattern = qr{
        (?m)                     ([+]{5})?(<\s?)
        (?<http_status_code>     (?&_http_status_code))    #  status code - required
                                 (\n<\s
        (?<response_header>      (?&_header))              # response header - optional
                                 )? 
        (?s)                     (\n
        (?<response_body>        (.*?)))?                  # response body - optional
        (?=                      (?: ([+]{5}|\Z)))
        (?-s)

    (?(DEFINE)
        (?<_http_status_code>    (\d+))
        (?<_header>              Content-Type:\s([a-z/]+))
    )
}x;

1;

package main;

use open qw/:std :utf8/;
use warnings FATAL => "utf8";
use Data::Dumper;

use lib qw/io::apiary com::mashape/;

#use re "log";

### create an alias for %+ for readability
our %MATCH;
*MATCH = \%+;

### paragraph mode
$/ = undef;

$| = 1;

our $DEBUG = 0;

eval {
    my $file = shift @ARGV;

    open( FILE, $file ) or die "Can't open file: $!\n";
    my $content = <FILE>;
    close FILE;

    my $endpoints = undef;
    my $models    = [];
    while ( $content =~ m/$section_pattern/gc ) {
        my $group     = $MATCH{name};
        my $resources = $MATCH{resources};
        printf( "%s\nGROUP %s\n%s\n", '*' x 40, $group, '*' x 40 ) if $DEBUG;

        ### Look for a model definitions

        print "=== MODEL START ===\n" if $DEBUG;
        my $long = $MATCH{long_desc};
        while ( $long =~ m/$model_pattern/gc ) {
            my $model = { name => $MATCH{name}, properties => {} };
            my $tail = $MATCH{tail};
            while ( $tail =~ m/$property_pattern/gc ) {
                $model->{properties}->{ $MATCH{name} } =
                  { type => $MATCH{type}, desc => $MATCH{desc} };
            }
            push @$models, $model;
        }
        if ($DEBUG) {
            print Dumper $models;
            print "=== MODEL END ===\n";
        }

        ### skip if there are no resources
        next unless ( length $resources > 0 );
        if ($DEBUG) {
            print "=== RESOURCES START ===\n";
            print Dumper $resources;
            print "=== RESOURCES END ===\n";
        }

        while ( $resources =~ m/$resource_pattern/gc ) {

            ### copy results into hash
            my %hash = %MATCH;
            if ($DEBUG) {
                print "-- RESOURCE START --\n";
                print Dumper %hash;
                print "-- RESOURCE END --\n";
            }
            ### do some cleaning up
            $hash{desc} =~ s/\n$//;

            ### parse signatures
            my $signatures = [];
            while ( $hash{signatures} =~ m/$signature_pattern/gc ) {
                my $signature = {
                    name     => $MATCH{name},
                    optional => defined $MATCH{required}
                      && $MATCH{required} eq 'required' ? 0 : 1,
                    desc => $MATCH{desc}
                };
                push @$signatures, $signature;
                if ($DEBUG) {
                    print "--- SIGNATURE START ---\n";
                    print Dumper $signature;
                    print "--- SIGNATURE END ---\n";
                }
            }
            $hash{signatures} = $signatures;

            ### parse actions
            my $actions         = $hash{actions};
            my $defined_actions = [];

            while ( $actions =~ m/$action_pattern/gc ) {

                my $action = {
                    http_status_code => $MATCH{http_status_code},
                    response_header  => defined $MATCH{response_header}
                    ? $MATCH{response_header}
                    : undef,
                    response_body => defined $MATCH{response_body}
                    ? $MATCH{response_body}
                    : undef
                };

                push @$defined_actions, $action;
                if ($DEBUG) {
                    print "--- ACTION START ---\n";
                    print Dumper $action;
                    print "--- ACTION END ---\n";
                }
            }
            $hash{actions} = $defined_actions;

            ### save resource together with group
            if ( exists $endpoints->{$group} ) {
                push @{ $endpoints->{$group} }, \%hash;
            }
            else {
                $endpoints->{$group} = [ \%hash ];
            }
        }
    }

    com::mashape::writeXml( $endpoints, $models );

};
if ($@) {
    print "Error: $@";
}

### TODO
### URI parameter can have several formats.
### See: http://support.apiary.io/knowledgebase/articles/106871-uri-templates-support
sub parseURI {

    # template.
    # example: GET /payment/{id}
    # matches: /payment/123

    # special case. example: GET /payment/123

    # querystring.
    # example: GET /payments{?year,month}
    # matches: /payments?year=2012&month=08

    # combination. example: GET /payments/customers/{customer_id}/{?year,month}

    # crosshair.
    # example: GET /payments/{#position}
    # matches: /payments#123

    # explode modifier.
    # example: GET /payments{?year*}
    # matches: /payments?year=2011&year=2012
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
