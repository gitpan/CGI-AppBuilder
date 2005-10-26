package CGI::AppBuilder;

# Perl standard modules
use strict;
use warnings;
use CGI::Carp qw(fatalsToBrowser warningsToBrowser);
use CGI;
use CGI::Pretty ':standard';
use CGI::Getopt qw(get_inputs read_init_file read_cfg_file); 
use Getopt::Std;
use Debug::EchoMessage qw(echo_msg debug_level 
    set_param disp_param :log);
use POSIX qw(strftime);

our $VERSION = 0.11;
warningsToBrowser(1);

require Exporter;
our @ISA         = qw(Exporter);
our @EXPORT      = qw();
our @EXPORT_OK   = qw(start_app end_app build_html_header disp_form
                   );
our %EXPORT_TAGS = (
    all  => [@EXPORT_OK]
);

=head1 NAME

CGI::AppBuilder - Configuration initializer 

=head1 SYNOPSIS

  use CGI::AppBuilder;

  my $cg = CGI::AppBuilder->new('ifn', 'my_init.cfg', 'opt', 'vhS:a:');
  my $ar = $cg->get_inputs; 

=head1 DESCRIPTION

There are already many application builders out there. Why you need 
another one? Well, if you are already familiar with CGI::Builder or
CGI::Application, this one will provide some useful methods to you to
read your configuration file and pre-process your templates. 
Please read on.

=cut

=head3 new (ifn => 'file.cfg', opt => 'hvS:')

Input variables:

  $ifn  - input/initial file name. 
  $opt  - options for Getopt::Std

Variables used or routines called:

  None

How to use:

   my $ca = new CGI::AppBuilder;      # or
   my $ca = CGI::AppBuilder->new;     # or
   my $ca = CGI::AppBuilder->new(ifn=>'file.cfg',opt=>'hvS:'); # or
   my $ca = CGI::AppBuilder->new('ifn', 'file.cfg','opt','hvS:'); 

Return: new empty or initialized CGI::AppBuilder object.

This method constructs a Perl object and capture any parameters if
specified. It creates and defaults the following variables:
 
  $self->{ifn} = ""
  $self->{opt} = 'hvS:'; 

=cut

sub new {
    my $caller        = shift;
    my $caller_is_obj = ref($caller);
    my $class         = $caller_is_obj || $caller;
    my $self          = bless {}, $class;
    my %arg           = @_;   # convert rest of inputs into hash array
    foreach my $k ( keys %arg ) {
        if ($caller_is_obj) {
            $self->{$k} = $caller->{$k};
        } else {
            $self->{$k} = $arg{$k};
        }
    }
    $self->{ifn} = ""     if ! exists $arg{ifn};
    $self->{opt} = 'hvS:' if ! exists $arg{opt};
    return $self;
}

=head3 start_app ($prg,$arg,$nhh)

Input variables:

  $prg  - program name 
  $arg  - array ref for arguments - %ARGV
  $nhh  - no html header pre-printed 
          1 - no HTML header is set in any circumstance
          0 - HTML header will be set when it is possible

Variables used or routines called:

  build_html_header - build HTML header array
  Debug::EchoMessage
    echoMSG  - echo messages
    start_log - start and write message log
  CGI::Getopt
    get_inputs - read input file and/or CGI form inputs
    

How to use:

   my ($q, $ar, $ar_log) = $self->start_app($0,\@ARGV);

Return: ($q,$ar,$ar_log) where 

  $q - a CGI object
  $ar - hash ref containing parameters from input file and/or 
        CGI form inputs and the following elements:
    ifn - initial file name
    opt - command input options
    cfg - configuratoin array
    html_header - HTML header parameters (hash ref)
    msg - contain message hash
  $ar_log - hash ref containing log information

This method performs the following tasks:

  1) initial a CGI object
  2) read initial file if specified or search for a default file
     (the same as $prg with .ini extension) and save the file name
     to $ar->{ifn}. 
  3) define message level
  4) start HTML header and body using I<page_title> and I<page_style>
     if they are defined.
  5) parse CGI form inputs and combine them with parameters defined
     in initial file
  6) read configuration file ($prg.cfg) if it exists and save the 
     array to $ar->{cfg}
  7) prepare log record if write log is enabled

It checks the parameters read from initial file for page_title, 
page_style, page_author, page_meta, top_nav, bottom_nav, and js_src. 

=cut

sub start_app {
    my $s = shift;
    my ($prg, $ar_arg, $nhh) = @_;
    my $args = ($ar_arg && $ar_arg =~ /ARRAY/)?(join " ", @$ar_arg):'';
    my $ifn = $prg; $ifn =~ s/\.(\w+)$/\.ini/;
    my $cfg = $prg; $cfg =~ s/\.(\w+)$/\.cfg/;
    my $opt  = 'a:v:hS:';
    my ($q, $ar);
    # 0. need to decide it is in verbose mode or not
    my $web_flag = 0; 
    if (exists $ENV{HTTP_HOST} || exists $ENV{QUERY_STRING}) {
        $q = CGI->new;
	my $v1 = $q->param('v');
	my $v2 = $q->Vars->{v}; 
	if ((defined($v1) && $v1) || (defined($v2) && $v2)) { 
	    $web_flag = 1;
            print $q->header("text/html") if !$nhh; 
	}
    }
    #
    # 1-3,5. Read initial file
    ($q,$ar) = $s->get_inputs($ifn,$opt);
    $s->echoMSG(" += Starting application...");
    $s->echoMSG(" ++ Reading initial file $ifn...")    if  -f $ifn;
    $s->echoMSG(" +  Initial file - $ifn: not found.") if !-f $ifn;
    # if user has defined messages in the initial file, we need to 
    # convert it into hash.
    $ar->{msg} = eval $ar->{msg} if exists $ar->{msg}; 

    # 4. start HTML header
    my %ar_hdr = $s->build_html_header($q, $ar); 
    $ar->{html_header} = \%ar_hdr   if ! exists $ar->{html_header}; 

    # 5. start the HTML page
    if (!$nhh && (
        exists $ENV{HTTP_HOST} || exists $ENV{QUERY_STRING})) { 
        print $q->header("text/html") if ! $web_flag;
	print $q->start_html(%ar_hdr), "\n";
        print $ar->{top_nav} if exists $ar->{top_nav} && $ar->{top_nav};
    }

    # 6. read configuration file
    if (-f $cfg) { 
        $s->echoMSG(" ++ Reading config file $cfg...");
        $ar->{cfg} = $s->read_cfg_file($cfg); 
    }

    # 7. set log array
    my ($ds,$log_dir,$log_brf, $log_dtl) = ('/',"","","");
       $log_dir = (exists ${$ar}{log_dir})?${$ar}{log_dir}:'.';
    my $lgf = $ifn; $lgf =~ s/\.\w+//; $lgf =~ s/.*\/(\w+)$/$1/;
    my $tmp = strftime "%Y%m%d", localtime time;
       $log_brf = join $ds, $log_dir, "${lgf}_brief.log";
       $log_dtl = join $ds, $log_dir, "${lgf}_${tmp}.log";
    my ($lfh_brf,$lfh_dtl,$txt,$ar_log) = ("","","","");
    if (exists ${$ar}{write_log} && ${$ar}{write_log}) {
        $ar_log = $s->start_log($log_dtl,$log_brf,"",$args,2);
    }
    $s->echoMSG($ar,3);
    $s->echoMSG($ar_log,3);
    return ($q,$ar,$ar_log);
}

=head3 end_app ($q, $ar, $ar_log)

Input variables:

  $q    - CGI object 
  $ar   - array ref for parameters 
  $ar_log - hash ref for log record

Variables used or routines called:

  Debug::EchoMessage
    echoMSG - echo messages
    end_log - start and write message log
    set_param - get a parameter from hash array

How to use:

   my ($q, $ar, $ar_log) = $self->start_app($0,\@ARGV);
   $self->end_app($q, $ar, $ar_log);

Return: none 

This method performs the following tasks:

  1) ends HTML document 
  2) writes log records to log files 
  3) close database connection if it finds DB handler in {dbh}

=cut

sub end_app {
    my $s = shift;
    my ($q, $ar, $ar_log) = @_;
    if (exists ${$ar}{write_log} && ${$ar}{write_log}) {
        $s->end_log($ar_log);
    }
    my $dbh = $s->set_param('dbh', $ar);
    $dbh->disconnect() if $dbh; 
    if (exists $ENV{HTTP_HOST} || exists $ENV{QUERY_STRING}) { 
        print $ar->{bottom_nav} if exists $ar->{bottom_nav}; 
        print $q->end_html;
    }
}

=head3 build_html_header ($q, $ar)

Input variables:

  $q    - CGI object 
  $ar   - array ref for parameters 

Variables used or routines called:

  Debug::EchoMessage
    echoMSG - echo messages
    set_param - get a parameter from hash array

How to use:

  my $ifn = 'myConfig.ini'; 
  my ($q,$ar) = $s->get_inputs($ifn);
  my $hrf = $self->build_html_header($q, $ar);

Return: hash array or array ref

This method performs the following tasks:

  1) check the following parameters: page_title, page_style, 
     page_meta, page_author, page_target, js_src, 
  2) writes log records to log files 
  3) close database connection if it finds DB handler in {dbh}

=cut

sub build_html_header {
    my $s = shift;
    my ($q, $ar) = @_;

    # 4. start HTML header
    my $title = $s->set_param('page_title', $ar);
       $title = "Untitled Page"            if ! $title;
    my $style = $s->set_param('page_style', $ar);
       $style = '<!-- -->'                 if ! $style;
    my $author = $s->set_param('page_author', $ar);
       $author = 'Hanming.Tu@Premier-Research.COM' if ! $author; 
    my $target = $s->set_param('page_target', $ar);
       # $target = '_blank'                  if ! $target; 
    my $js_src = $s->set_param('js_src', $ar);
    my $yr = strftime "%Y", localtime time;
    my $meta_txt = $s->set_param('page_meta', $ar);
    my $mrf = {}; 
    if ($meta_txt) { 
       $mrf = eval $meta_txt; 
       $mrf->{'keywords'} = 'Perl Modules';
       $mrf->{'copyright'}= "copyright $yr Hanming Tu"; 
    } else { 
       $mrf = {'keywords'=>'Perl Modules',
         'copyright'=>"copyright $yr Hanming Tu"}; 
    }
    my %ar_hdr = (-title=>$title, -author=>$author, -meta=>$mrf);  
    $ar_hdr{-target}= $target    if $target;
    $ar_hdr{-style} = ($style =~ /^<!--/) ? $style : {'src'=>"$style"}; 
    if ($js_src) {
        if (index($js_src, ',') > 0) { 
            my @js = map {
              {-language=>'JavaScript1.2', -src=>$_}
            } (split /,/, $js_src); 
            $ar_hdr{-script} = \@js;
        } else { 
            $ar_hdr{-script} = 
                {-language=>'JavaScript1.2', -src=>$js_src}; 
        }
    }
    $ar->{html_header} = \%ar_hdr; 
    return wantarray ? %ar_hdr : \%ar_hdr; 
}

=head3 disp_form ($q, $ar)

Input variables:

  $q    - CGI object 
  $ar   - array ref for parameters 

Variables used or routines called:

  Debug::EchoMessage
    echoMSG - echo messages
    set_param - get a parameter from hash array

How to use:

  my $ifn = 'myConfig.ini'; 
  my ($q,$ar) = $s->get_inputs($ifn);
  $self->disp_form($q, $ar);

Return: none 

This method expects the following varialbes:

  gi - GUI items
  gc - GUI columns
  gf - GUI form
  db - database connection varialbes (optional)
  vars_keep - variables separated by comma for hidden variables

This method performs the following tasks:

  1) checks whether GI, GC and GF variables being defined. 
  2) replaces AR, DB, GI, and GC variables with their contents
  3) builds GF elements 
  4) add hidden variables
  5) print the form

=cut

sub disp_form {
    my $s = shift;
    my ($q, $ar) = @_;

    # check required GUI variables
    foreach my $k (split /,/, 'gi,gc,gf') {
        next if exists $ar->{$k};
        print h1("GUI element - {$k} is not defined");
        return;
    }
    if ($ar->{gi} =~ /db->/ && ! exists $ar->{db}) {
        print h1("GUI element - {db} is not defined");
        return;
    }
    # process GUI AR items
    $ar->{gk} =~ s/ar->/\$ar->/g;
    $ar->{gi} =~ s/ar->/\$ar->/g;
    $ar->{gc} =~ s/ar->/\$ar->/g;
    $ar->{gf} =~ s/ar->/\$ar->/g;

    # process GUI DB items
    $ar->{gk} =~ s/db->/\$db->/g;
    $ar->{gi} =~ s/db->/\$db->/g;
    $ar->{gc} =~ s/db->/\$db->/g;
    $ar->{gf} =~ s/db->/\$db->/g;

    # process GUI GK items
    $ar->{gi} =~ s/gk->/\$gk->/g;
    $ar->{gc} =~ s/gk->/\$gk->/g;
    $ar->{gf} =~ s/gk->/\$gk->/g;

    # process GUI GI items
    $ar->{gc} =~ s/gi->/\$gi->/g;
    $ar->{gf} =~ s/gi->/\$gi->/g;

    # process GUI GC items
    $ar->{gf} =~ s/gc->/\$gc->/g;

    my $db = "";
       $db = $ar->{db} if exists $ar->{db} && $ar->{db}; 

    my $gk = eval $ar->{gk};
        $s->echoMSG($gk,5);
    my $gi = eval $ar->{gi};
    if ($gi !~ /HASH/) {
        $s->echoMSG($ar->{gi},2);
        $s->echoMSG("GI not properly defined." ,1);
    } else {
        foreach my $k (%$gi) {
            next if ($k !~ /^x(td|cp)_(.+)/i); 
            my ($k1, $k2) = ($1, $2); 
            if ($k1 =~ /^td/i) { 
                my @a = @{$gi->{$k2}}; 
                if ($gi->{$k} =~ /^radio_group/i) { 
                    $gi->{$k} = radio_group(@a);
                } elsif ($gi->{$k} =~ /^popup_menu/i) {
                    $gi->{$k} = popup_menu(@a);
                } else {
                    $gi->{$k} = td(@a);
                }
            } else {
                my $txt = "";
                foreach my $i (split /,/, $gi->{$k}) { 
                    $txt .= $gi->{$i}; 
                }
                $gi->{$k} = $txt; 
            }
        }
        $s->echoMSG($ar->{gi},5);
        $s->echoMSG($gi,5);
    }
    my $gc = eval $ar->{gc};
    if ($gc !~ /HASH/ || ! exists $gc->{td}) {
        $s->echoMSG($ar->{gc},2);
        $s->echoMSG("GC not properly defined." ,1);
    } else {
        $s->echoMSG($ar->{gc},5);
        $s->echoMSG($gc,5);
    }
    $s->echoMSG($ar->{gf},5);
    my $gf = eval $ar->{gf};

    my $fmn = 'fm1';
       $fmn = $ar->{form_name} 
         if exists $ar->{form_name} && $ar->{form_name}; 
    print "<center>\n";
    print start_form( -name  => $fmn, -method=>uc $ar->{method},
        -action=>"$ar->{action}?", -enctype=>$ar->{encoding} );
    my $hvs = $s->set_param('vars_keep', $ar);
    if ($hvs) {
        foreach my $k (split /,/, $hvs) {
            my $v = $s->set_param($k, $ar);
            next if $v =~ /^\s*$/;
            print hidden($k,$v);
        }
    }
    print "$gf\n";
    print end_form;
    print "</center>\n";
    return;
}

1;

=head1 HISTORY

=over 4

=item * Version 0.10

This version is to extract out the app methods from CGI::Getopt class.
It was too much for CGI::Getopt to include the start_app, end_app,
build_html_header, and disp_form methods. 

=item * Version 0.11

Rewrote start_app method so that content-type can be changed.

=cut

=head1 SEE ALSO (some of docs that I check often)

CGI::Getopt, Oracle::Loader, Oracle::Trigger, CGI::AppBuilder, 
File::Xcopy, Debug::EchoMessage

=head1 AUTHOR

Copyright (c) 2005 Hanming Tu.  All rights reserved.

This package is free software and is provided "as is" without express
or implied warranty.  It may be used, redistributed and/or modified
under the terms of the Perl Artistic License (see
http://www.perl.com/perl/misc/Artistic.html)

=cut


