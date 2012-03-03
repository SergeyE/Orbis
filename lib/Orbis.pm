package Orbis;
use strict;
use HTTP::Request::Common;
use LWP::UserAgent;
  

sub post_xml {
    
    # Create a request
    my $self = shift;
    my @par = @_;
#    if ($par[0)
#    my $xml = $par[1];
    if ($par[3] !~ m#<\?xml# ) { $par[1] = qq(<?xml version="1.0" encoding="utf-8" standalone="yes"?>\n) . $par[3]; }

    my $req = POST $self->{service_uri}, 
    [
    login=>$self->{login}, 
    pass=>$self->{pass}, 
#    login=>"b2c", pass=>"b2c",
    dominio=>$self->{dominio}, 
    owb_modulo=>"ws", 
    @par
    ];
    my $res = $self->{ua}->request($req);
                    
    # print STDERR $req->as_string;

    # Check the outcome of the response
    if ($res->is_success) {
        # print STDERR "OK\n";
        return $res->content;
    }
    else {
        print STDERR "error!\n";
        dump_post_req($req, "error.html");
        return $res->status_line, "\n";
    }
    
}

sub xml_reserva {
    my ( $self, $xml) = @_;
    return $self->post_xml(
        owb_vista => "reservas", 
        "xml_reserva_ws" => 
            qq($xml\n), 
    ); 
}

sub xml_integracion {
  my ( $self, $xml) = @_;
  return $self->post_xml(                         
      owb_vista => "integracion", 
      "xml_integracion_ws" => 
      qq($xml\n),
  );
   
}


sub new {
    my $class=shift(@_);
    my $self={@_};
    $self->{service_uri} ||= 'http://tmt.terramartour.com/owbooking/index.php';
    $self->{dominio} ||= 'tmt';
    $self->{ua} = LWP::UserAgent->new;

    $self->{id_tipo_articulo_clase} = 2;
    $self->{SKIP_EMPTY_PRESTATARIOS} = 0;
    
    bless($self,$class);
    return $self;
}

# получаем arrayref с отелями в соответствии с запросом $req 

sub get_prestatarios {
    my $self = shift;
    my $req = shift;
    warn("get_prestatarios") if $self->{DEBUG}; 
    if (!defined  $req->{zona_id} && defined $req->{zona}) { $req->{zona_id} = $self->get_zona_id($req->{zona}); }
    my $query = qq(<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<integracion accion="prestatarios">
<id_tipo_articulo_clase>$self->{id_tipo_articulo_clase}</id_tipo_articulo_clase>
<provincia>$req->{provincia}</provincia>
<id_zona>$req->{zona_id}</id_zona>
<info_extendida>1</info_extendida>
<poblacion>) . $req->{poblacion}  . qq(</poblacion>
<id_idioma>3</id_idioma>                               
</integracion>);
    my $prests = $self->xml_integracion($query);
    if (length($prests) > 300) { # если получен длинный ответ, значит разбираем
    # save_arrayref("prestatarios.xml", [ $prests ]);
    } elsif ($prests =~ m#error#) { warn("error for qurey:$query\nresp:$prests"); }
    else { 
       print STDERR "\rzero prestatarios for zona_id $req->{zona_id} (zona:$req->{zona}, pobl:$req->{poblacion})\n"; 
    }
    my @result;
    while ($prests =~ m#<prestatario>(.*?)</prestatario>#sg) {
       my $p = $1;
       my $row = {};
       while ($p =~ m#<(.+?)>(.*?)</(.+?)>#g) {
           if ($1 ne $3) { warn "need to fix re: $1 ne $3"; }
           $row->{$1} = $2;
       }

       $row -> { id } = $row->{id_prestatario};


       if ($p =~ m#<articulos_asociados>(\d+)</articulos_asociados>#s) {
           if ($self->{SKIP_EMPTY_PRESTATARIOS}) { next if $1 == 0; }
           $row->{articulos_asociados} = $1;
       }                     
       # warn ("$row->{categoria}, $row->{articulos_asociados}");
       push @result, $row;

    }

    return \@result;
}


# список стран
sub get_paises {
    my $self = shift;
    my $id_tipo_articulo_clase = shift || $self->{id_tipo_articulo_clase};
    my @res;
    my $resp =                                 
    $self->xml_integracion(qq(<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<integracion accion="paises">
<id_tipo_articulo_clase>$id_tipo_articulo_clase</id_tipo_articulo_clase>
<id_idioma>$self->{id_idioma}</id_idioma>
</integracion>
));
    # save_arrayref("articulos${id_prestatario}.xml", [ $ars ]);
    if (length($resp) < 600) { warn("zero paises for $id_tipo_articulo_clase en: [[$resp]]"); }
    while ($resp =~ m#<pais>.*?<id_zona_pais>(\d+)</id_zona_pais>.*?<nombre>(.*?)</nombre>.*?</pais>#sg) {
            my $row = {};
            $row->{id_zona_pais} = $1;
            $row->{nombre} = $2;
            push @res, $row;
    }
    return \@res;
}


# получаем список зон по номеру страны (id_zona_pais)
# возвращаем ссылку на массив хешей [ { id_zona, nombre }, ... ];
sub get_zonas {
    my $self = shift;
    my $id_zona_pais = shift;
    my @res;
    my $resp =                                 
    $self->xml_integracion(qq(<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<integracion accion="zonas">
<id_tipo_articulo_clase>$self->{id_tipo_articulo_clase}</id_tipo_articulo_clase>
<id_zona_pais>$id_zona_pais</id_zona_pais>
</integracion>
));
    # save_arrayref("articulos${id_prestatario}.xml", [ $ars ]);
    if ($resp !~ m#<zona>.+</zona>#s) { warn("zero zonas for $id_zona_pais: [[$resp]]"); }
    while ($resp =~ m#<zona>.*?<id_zona>(\d+)</id_zona>.*?<nombre>(.*?)</nombre>.*?</zona>#sg) {
            my $row = {};
            $row->{id_zona} = $1;
            $row->{nombre} = $2;
            push @res, $row;
    }
    return \@res;
}

# список названий городов по id_zona
sub get_poblaciones {
    my $self = shift;
    my $id_zona = shift;
    my $reqx = qq(<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<integracion accion="poblaciones">
<id_tipo_articulo_clase>$self->{id_tipo_articulo_clase}</id_tipo_articulo_clase>
<id_zona>$id_zona</id_zona>
</integracion>
);
    my $resp = 
    $self->xml_integracion($reqx);
    my @res;
    
    while ($resp =~ m#<poblacion>(.*?)</poblacion>#sg) {
            push @res, $1;
    }
    if ($#res == -1) { warn "zero poblaciones for zona $id_zona: ??$reqx??\n[[$resp]]" }
    elsif ($self->{DEBUG}) { print STDERR "got poblaciones ",($#res+1)," for zona $id_zona\n" if $self->{DEBUG}; }
    return \@res;
}

sub dump_post_req {

}


sub get_reservas {

    my $self = shift;
    my $req = shift;
    $req->{fecha_reserva_desde} ||= "2012-01-01";
    $req->{fecha_reserva_hasta} ||= "2037-01-01";
    $req->{fecha_inicio_servicio_desde} ||= "2012-01-01";
    $req->{fecha_inicio_servicio_hasta} ||= "2037-01-01";

    my $reqx = qq(<integracion accion="reservasfecha">
<fecha_reserva_desde>$req->{fecha_reserva_desde}</fecha_reserva_desde>
<fecha_reserva_hasta>$req->{fecha_reserva_hasta}</fecha_reserva_hasta>
<fecha_inicio_servicio_desde>$req->{fecha_inicio_servicio_desde}</fecha_inicio_servicio_desde>
<fecha_inicio_servicio_hasta>$req->{fecha_inicio_servicio_hasta}</fecha_inicio_servicio_hasta>
<update_modification>$req->{update_modification}</update_modification>
</integracion>
);
    my $resp = 
    $self->xml_integracion($reqx);
    my @res;
    
    while ($resp =~ m#<reserva>(.*?)</reserva>#sg) {
            push @res, $1;
    }

#    if ($#res == -1) { warn "zero poblaciones for zona $id_zona: ??$reqx??\n[[$resp]]" }
#    elsif ($self->{DEBUG}) { print STDERR "got poblaciones ",($#res+1)," for zona $id_zona\n" if $self->{DEBUG}; }
    return \@res;


}
1;