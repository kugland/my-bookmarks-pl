#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;
use utf8;
use autodie;
use open qw{ :encoding(UTF-8) :std };

use URI;
use English qw{ -no_match_vars };
use IPC::Open2 qw{ open2 };
use List::Util qw{ pairmap };
use Env qw{ HOME };
use Getopt::Long qw{ :config gnu_getopt no_auto_abbrev no_ignore_case };

my $ROFI_THEME = undef;

my $bookmarks   = "$HOME/.my-bookmarks.txt";
my $rofi        = 'rofi';
my $browser     = 'xdg-open';
my $tor_browser = undef;


sub load_bookmarks {
  open my $fh, '<', $bookmarks or die "Can’t open $bookmarks: $ERRNO\n";
  my @list = <$fh>;
  close $fh;
  @list =
    map  { s{ \A : \s* }{}msxgr }                   # remove leading colons
    grep { length $_ > 0 }                          # remove empty lines
    grep { !m{ \A [#] }msx }                        # remove comments
    map  { s{ \A \s* }{}msxgr }                     # remove leading whitespace
    map  { s{ \s* \z }{}msxgr }                     # remove trailing whitespace
    map  { s{ \s+ }{ }msxgr }                       # collapse whitespace
    @list;
  @list = pairmap { "$a\n<small>$b</small>\000" } @list;  # Make lines
  @list = sort @list;                               # Sort lines
  return join q{}, @list;
} ## end sub load_bookmarks


sub pipe_to_rofi {
  my ($content) = @_;
  my @rofi = ( $rofi, qw{ -dmenu -i -sep \x00 -no-custom -p bookmarks -theme-str }, $ROFI_THEME );
  my $pid = open2( my $rx, my $tx, @rofi ) or do die "Can’t open rofi: $ERRNO\n";
  binmode $rx, ':raw:encoding(UTF-8)';
  binmode $tx, ':raw:encoding(UTF-8)';
  print {$tx} $content;
  close $tx;
  my $result = do { local $RS = undef; <$rx> };
  close $rx;
  return ( ( $CHILD_ERROR >> 8 ) != 0 ) ? undef : $result;
} ## end sub pipe_to_rofi


sub notify {
  my ( $title, $message ) = @_;
  exec 'notify-send', '-t', '3000', $title, $message or 1;
}


sub handle_response {
  my ($response) = @_;
  my ( $title, $url ) = split qr/\n/msx, $response;
  if ( defined $url ) {
    $url =~ s{ \A \Q<small>\E (.*) \Q</small>\E \z }{$1}msx;
    local $ENV{URL} = $url;
    my $parsed_url = URI->new($url);
    if ( $parsed_url->host !~ / [.]onion \z /msx ) {
      exec qq{$browser "\$URL"} or 1;
    } elsif ( defined $tor_browser ) {
      exec qq{$tor_browser "\$URL"} or 1;
    } else {
      exec 'notify-send', '-t', '3000', 'Can’t open bookmark', 'Tor Browser not provided.' or 1;
    }
  } ## end if ( defined $url )
} ## end sub handle_response


sub main {
  Getopt::Long::GetOptions(
    'bookmarks=s'   => \$bookmarks,
    'rofi=s'        => \$rofi,
    'browser=s'     => \$browser,
    'tor-browser=s' => \$tor_browser,
    'help'          => sub {
      print <<~";;";
        Usage: $PROGRAM_NAME [options]

        Options:
            --bookmarks <file>    Path to bookmarks file
            --rofi <path>         Path to rofi executable
            --browser <path>      Path to browser executable
            --tor-browser <path>  Path to Tor Browser executable
            --help                Show this help message
        ;;
      exit 0;
    },
  ) or die "Try '$PROGRAM_NAME --help' for more information.\n";

  my $response = pipe_to_rofi( load_bookmarks() );
  handle_response($response) if defined $response;
  return 0;
}


$ROFI_THEME = <<';;';
  * { foreground: White; }
  window {
    background-color: rgba (50, 50, 50, 95%);
    width: 900;
    height: 600;
    border: 1;
    border-color: Black/50%;
    border-radius: 10;
  }
  listview { border: 0; spacing: 25; }
  element { border: 0; }
  element normal.normal { background-color: transparent; }
  element selected.normal { background-color: White/6%; text-color: var(normal-foreground); }
  element alternate.normal { background-color: transparent; }
  element-text { padding: 0px 8px; background-color: inherit; text-color: inherit; markup: true; }
  scrollbar { handle-color: White/30%; }
  inputbar { padding: 8; children: [ "prompt","textbox-prompt-colon","entry","case-indicator" ]; }
  textbox-prompt-colon { str: " ⟩ "; }
;;


exit main();
