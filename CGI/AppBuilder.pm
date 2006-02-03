package CGI::AppBuilder;

# Perl standard modules
use strict;
use warnings;
use Getopt::Std;
use POSIX qw(strftime);
use CGI;
use CGI::Carp qw(fatalsToBrowser warningsToBrowser);
use CGI::Pretty ':standard';
use CGI::AppBuilder::Config   qw(:all); 
use CGI::AppBuilder::Message  qw(:all); 
use CGI::AppBuilder::Log      qw(:all); 
use CGI::AppBuilder::Form     qw(:all); 
use CGI::AppBuilder::Table    qw(:all); 
use CGI::AppBuilder::Header   qw(:all); 
use CGI::AppBuilder::Frame    qw(:all); 

our $VERSION = 0.12;
warningsToBrowser(1);

require Exporter;
our @ISA         = qw(Exporter);
our @EXPORT      = qw(start_app end_app);
our @IMPORT_OK = (@CGI::AppBuilder::Config::EXPORT_OK,
    @CGI::AppBuilder::Message::EXPORT_OK, 
    @CGI::AppBuilder::Log::EXPORT_OK, 
    @CGI::AppBuilder::Form::EXPORT_OK, 
    @CGI::AppBuilder::Table::EXPORT_OK, 
    @CGI::AppBuilder::Header::EXPORT_OK, 
    @CGI::AppBuilder::Frame::EXPORT_OK 
);
our @EXPORT_OK   = (qw(start_app end_app),@IMPORT_OK);
our %EXPORT_TAGS = (
    app      => [qw(start_app end_app build_html_header)],
    config   => [@CGI::AppBuilder::Config::EXPORT_OK],
    echo_msg => [@CGI::AppBuilder::Message::EXPORT_OK],
    log      => [@CGI::AppBuilder::Log::EXPORT_OK],
    form     => [@CGI::AppBuilder::Form::EXPORT_OK],
    table    => [@CGI::AppBuilder::Table::EXPORT_OK],
    header   => [@CGI::AppBuilder::Header::EXPORT_OK],
    frame    => [@CGI::AppBuilder::Frame::EXPORT_OK],
    all      => [@EXPORT_OK, @IMPORT_OK]
);

=head1 NAME

CGI::AppBuilder - CGI Application Builder 

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
    echo_msg  - echo messages
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
    $s->echo_msg(" += Starting application...");
    $s->echo_msg(" ++ Reading initial file $ifn...")    if  -f $ifn;
    $s->echo_msg(" +  Initial file - $ifn: not found.") if !-f $ifn;
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
        $s->echo_msg(" ++ Reading config file $cfg...");
        $ar->{cfg} = $s->read_cfg_file($cfg); 
    }

    # 7. set log array
    my ($ds,$log_dir,$log_brf, $log_dtl) = ('/',"","","");
       $log_dir = (exists ${$ar}{log_dir})?${$ar}{log_dir}:'.';
    my $lgf = $ifn; $lgf =~ s/\.\w+//; $lgf =~ s/.*[\/\\](\w+)$/$1/;
    my $tmp = strftime "%Y%m%d", localtime time;
       $log_brf = join $ds, $log_dir, "${lgf}_brief.log";
       $log_dtl = join $ds, $log_dir, "${lgf}_${tmp}.log";
    my ($lfh_brf,$lfh_dtl,$txt,$ar_log) = ("","","","");
    if (exists ${$ar}{write_log} && ${$ar}{write_log}) {
        $ar_log = $s->start_log($log_dtl,$log_brf,"",$args,2);
    }
    $s->echo_msg($ar,5);
    $s->echo_msg($ar_log,5);
    return ($q,$ar,$ar_log);
}

=head3 end_app ($q, $ar, $ar_log, $nhh)

Input variables:

  $q    - CGI object 
  $ar   - array ref for parameters 
  $ar_log - hash ref for log record
  $nhh  - no html header pre-printed 
          1 - no HTML is printed in any circumstance
          0 - HTML header will be printed when it is possible

Variables used or routines called:

  Debug::EchoMessage
    echo_msg - echo messages
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
    my ($q, $ar, $ar_log, $nhh) = @_;
    if (exists ${$ar}{write_log} && ${$ar}{write_log}) {
        $s->end_log($ar_log);
    }
    my $dbh = $s->set_param('dbh', $ar);
    $dbh->disconnect() if $dbh; 
    if (exists $ENV{HTTP_HOST} || exists $ENV{QUERY_STRING}) { 
        print $ar->{bottom_nav} if exists $ar->{bottom_nav} && !$nhh; 
        print $q->end_html   if !$nhh;
    }
}

1;

=head1 HISTORY

=over 4

=item * Version 0.10

This version is to extract out the app methods from CGI::Getopt class.
It was too much for CGI::Getopt to include the start_app, end_app,
build_html_header, and disp_form methods. 

  0.11 Rewrote start_app method so that content-type can be changed.
  0.12 Moved disp_form to CGI::AppBuilder::Form,
       moved build_html_header to CGI::AppBuilder::Header, and 
       imported all the methods in sub-classes into this class.

=item * Version 0.20

=cut

=head1 SEE ALSO (some of docs that I check often)

Oracle::Loader, Oracle::Trigger, CGI::Getopt, File::Xcopy,
CGI::AppBuilder, CGI::AppBuilder::Message, CGI::AppBuilder::Log,
CGI::AppBuilder::Config, etc.

=head1 AUTHOR

Copyright (c) 2005 Hanming Tu.  All rights reserved.

This package is free software and is provided "as is" without express
or implied warranty.  It may be used, redistributed and/or modified
under the terms of the Perl Artistic License (see
http://www.perl.com/perl/misc/Artistic.html)

=cut


