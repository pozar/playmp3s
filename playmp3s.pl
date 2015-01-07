#!/usr/local/bin/perl 

# $Id: playmp3s.pl,v 1.39 2010/08/09 16:15:35 pozar Exp $
#
# This script reads in a playlist file and randomly plays a cut from 
# the list.  You can tell it not to repeat a cut/artist from "n" number 
# plays back.
#
# The script will also do back announcing of the cuts played ever "n" 
# minutes or cuts depending which ever is first.
#
# A "last played" HTML file is also created for folks wondering what 
# that cut was.
#
# This script depends on a number of other programs...
#    date - Standard UNIX "date" program
#       To figure how what time it is an how long has something been going on.
#
#    wc - Standard UNIX word and line count program
#       To count various things like how many cuts in a playlist.
#
#    festival - A text to speech synthesis program - 
#       http://www.cstr.ed.ac.uk/projects/festival
#       To back-announce and do station IDs for this script.
#       By default, festival will want to use the NASd audio server.  You can 
#       just add:
#		(Parameter.set 'Audio_Method 'freebsd16audio)
# 	or
#		(Parameter.set 'Audio_Method 'linux16audio)
#	to the /usr/local/share/festival/lib/siteinit.scm file.
#
#    mpg123 - An MP3 player - http://www.mpg123.de
#       To play the chosen MP3 file.
#
#    id3info - id3 v1/3 info display
#       To read the id3 tag from an MP3 file.
#
#    mpck - Gives data about an MP3 file.  
#       I use it to tell the script how long in minutes an MP3 file is.
#
#    Text/Striphigh.pm - is usually not in the standard distribution of perl.  
#    You need to add it.
# 
# Things to do...
# 
# * Show breaks on the HTML page?
# 
# * Have all of the audio generating program send to STDOUT so we
#   can redirect it to an ICECAST relay.
#
# * The script should read a config file to determine what the
#   current playlist is and other options like if it should play it
#   randomly or sequentially, how far to go back.  The config file
#   should be read with a "kill -HUP <PID>".
# 
# Bugs...
# Seems that mpg123 wants to kick start esd if it finds it out there
# and have it respawn.  This means that after a while you will find
# a number of esd processes running and mpg123 wedged.  To fix this
# make sure the line in esd.conf looks like:
# 
#	auto_spawn=0
#

# Text/Striphigh.pm is usually not in the standard distribution of perl.  You need to add it.
use Text::Striphigh 'striphigh';

$debug = 1;

$saidtime = 0;
$hour=`date "+%H"`; 
chop($hour);
$time = time;

$dobreak = 20 * 60;	# Do a break at least every 20 minutes (in seconds)...
$songsbeforebreak = 5;	# Or do a break every 4 cuts.  Whichever comes first.

$playlist = "/usr/local/public/audio/iTunes/current.m3u";
$cutsplayedlog = "/var/log/playmp3s/cutsplayed.log";
$fulllog = "/var/log/playmp3s/cuts.log";
$lookback = 200;                # How many lines to look back in
				# the log for duplicate songs and
				# artists that we should skip.  400
				# is about 24 hours for 4 cuts or 20
				# minutes between breaks.

$artist_cutname_ratio = .25;	# If this number is less than "1"
				# the program will look for cut
				# name duplicates only for the ratio.
				# For instance, if it is ".25" and
				# $lookback = 300 then for the first
				# 225 lines, the program will look
				# at cut name dups and then the nearest
				# 75 cuts to the current time, it
				# will look for both cut name and
				# artist name duplicates.  Of course,
				# this "feature" is meant to support
				# more frequent artist plays than cut
				# titles.

$htmlpage = "/usr/local/www/apache22/data/index.html";	# The HTML page to update.
$htmllookback = 100;		# How many lines to look back in the log for the HTML page?

$ctime=`date`; 
if ($debug > 0){
	print "The script started at: $ctime";
}
# The loop...

while (1){
	sleep(2);
	&break;
	&news;
	&randomplay;
}

sub break {
	$newtime = time;
	# Don't do a break less than 3 songs or less than $dobreak seconds 
	# which ever is less.  How many have we played so far?  Count the 
	# entries in $cutsplayedlog so if we restart the program we know.
	$_ = `wc $cutsplayedlog`;
	chop;
	tr/ / /s;
	($foo1, $numofcuts) = split(/ /);
	if ($numofcuts != 0){
		if (($numofcuts >= $songsbeforebreak) || ($dobreak <= ($newtime - $time))) {

			$ctime=`date`; 
			chop($ctime);
			open (FULLLOG, ">>$fulllog");
			print FULLLOG "$ctime - Break\n";
			if ($debug > 0){
				print "$ctime - Break\n";
			}
			close (FULLLOG);

			sleep 2;
			# Do an ID...
			`echo "You are listening to K-U-M-R." | /usr/local/bin/festival --tts`;

			# Back announce...
			stat($cutsplayedlog);
			if (-s _){
				`echo "From the last break you heard" | /usr/local/bin/festival --tts`;
 				open (CUTSPLAYEDLOG, $cutsplayedlog);
				$firstloop = 1;
       				while (<CUTSPLAYEDLOG>) {

					# If you come across a "&" replace it with a " and " as 
					# Festivial says "ampersand" for "&".  Include some spaces 
					# either side of the "&" so you can squish things into the ID3 tags.
					s/\&/ and /g;
	
					if (($numofcuts == 1) && ($firstloop == 0)){
						`echo "and finally," | /usr/local/bin/festival --tts`;
					}
					($artist,$album,$cutname) = split(/	/);
					`echo "$artist, $cutname" | /usr/local/bin/festival --tts`;
					$numofcuts--;
					$firstloop = 0;
       				}
				close(CUTSPLAYEDLOG);
				unlink $cutsplayedlog;
			}

			# Do a time check...
			$result = `/usr/local/bin/festival --batch /usr/local/share/festival/examples/saytime`;
			sleep 1;
			if ($debug > 0){
				print $result;
			}
		} else {
			$saidtime++;
		}
	}
	$time = $newtime;
}

sub news {
	$newhour=`date "+%H"`; 
	chop($newhour);
	if($hour eq $newhour){
	} else {
		# Do a break.
		$time = 0;
		&break;

		$ctime=`date`; 
		chop($ctime);
		open (FULLLOG, ">>$fulllog");
		print FULLLOG "$ctime - News\n";
		if ($debug > 0){
			print "$ctime - News\n";
		}
		close (FULLLOG);
		if ($debug > 0){
			print "Doing the news...\n";
		}

		`echo "Here is the latest news from Associated Press." |  /usr/local/bin/festival --tts`;

		$ap_out = "/tmp/latest_ap";
		# Grab the RSS feed from AP...
		`wget -O - "http://hosted.ap.org/lineups/TOPHEADS-rss_2.0.xml?SITE=RANDOM&SECTION=HOME" | grep entry-content > $ap_out`;
		open (AP_OUT, $ap_out) || die "can't open $ap_out";
		while (<AP_OUT>) {
			chomp;
			s/&lt;div class="entry-content"&gt;//g;
			s/...&lt;\/div&gt;//g;
			s/ \(AP\) //g;
			`echo "$_" |  /usr/local/bin/festival --tts`;
		}
		close(AP_OUT);

		$saidtime = 0;
		sleep 1;
		$hour = $newhour;
	}
}

sub randomplay {
	`killall mpg123`;
	$_ = `wc $playlist`;
	chop;
	tr/ / /s;
	($foo1, $maxlines) = split(/ /);
	$result = $_;
	if ($maxlines < $lookback) {
		$lookbackidx = $maxlines;
		$lookbackartistidx = $maxlines - ($maxlines * $artist_cutname_ratio);
	} else {
		$lookbackidx = $lookback;
		$lookbackartistidx = $lookback - ($lookback * $artist_cutname_ratio);
	}
	$matchrecent = 1;
	SELECTCUT: while (1){
		$randline_float = rand $maxlines;
		($randline) = split(/\./,$randline_float);
		$i = 0;
		open (MP3LIST, $playlist) || die "can't open list of MP3s";
		while ($i <= $randline) {
			$_ = <MP3LIST>;
			$i = $i + 1;
		}
		chop;
		$cut = $_;

		$cutname = "";
		$artist = "";
		$album = "";

		# Parse for an ID3 Tag...
		open (ID3TAG, "id3info \"$cut\"|");
		while (<ID3TAG>) {
			chop;
			s/	/ /g;			# replace any tabs with a 
							# single space as we use 
							# tabs to demarc fields in 
							# the log files.
			$foo = $_;			# This is ugly. Fix it
         		$_ = striphigh($foo);
			($key, $data) = split(/: /);
			$_ = $key;
			if (/Title/s) { 
				$cutname = $data;
			}
			if (/performer/s) { 
				$artist = $data;
			}
			if (/Album/s) { 
				$album = $data;
			}
		}
		if ($debug > 0){
			print "Matching for Cutname = \"$cutname\", Artist = \"$artist\" or Album = \"$album\",\nof the file \"$cut\" with:\n";
		}
		$matchrecent = 0;
		open(RECENT, "tail -$lookbackidx $fulllog | grep \"	\" |");
		while(<RECENT>){
			chop;
			$foo = $_;			# This is ugly. Fix it
         		$_ = striphigh($foo);
			$recent_cutname = "";
			if (m/.*	/){
				($recent_time,$recent_artist,$recent_album,$recent_cutname) = split(/	/);
				# This condition if for backwards compatibility for the old log format...
				if ($recent_cutname eq ""){
					$recent_cutname = $recent_album;
					$recent_album = $recent_artist;
					$recent_artist = $recent_time;
				}
			} else {
				$recent_artist = $_;
				$recent_cutname = $_;
			}
			if (!(/ - Break$/s)) {
				if ($debug > 0){
					print "	\"$_\"\n";
				}
				if (($cutname eq "") && ($artist eq "")){
					# Parse $cut for the last part of the file name and search for it in $fulllog.
					# Right now just skip out of this loop
					$matchrecent = 0;
					last;
				} else {
					$cutname_s = $cutname;
					$cutname_s =~ tr/\&\^\$\(\)\:\-\\\[\]\{\}\'\"/./;
					$_ = $recent_cutname;
					if (/$cutname_s/s) { 
						$matchrecent = 1; 
						if ($debug > 0){
							print "  $cutname_s matches $_\n";
						}
						last;
					}
					# if ($lookbackartistidx < 1){
						$artist_s = $artist;
						$artist_s =~ tr/\&\^\$\(\)\:\-\\\[\]\{\}\'\"/./;
						$_ = $recent_artist;
						if (/$artist_s/s) { 
							$matchrecent = 1; 
							if ($debug > 0){
								print "  $artist_s matches $_\n";
							}
							last;
						}
					# }
				}
			}
		}
		if ($matchrecent == 1) { 
			if ($debug > 0){
				print "	Skipped:\n   \"$cut\"\nas it is too close to:\n   \"$recent_artist\" \"$recent_cutname\".\n";
			}
			# Don't drop to negative numbers.
			if ($lookbackidx > 0){		
				# We don't want to loop indefinity if we 
				# can't find a cut.
				--$lookbackidx;		
			}
			# Don't drop to negative numbers.
			if ($lookbackartistidx > 0){		
				# We don't want to loop indefinity if we 
				# can't find a cut.
				--$lookbackartistidx;		
			}
			print "lookbackidx = $lookbackidx , lookbackartistidx = $lookbackartistidx\n";
			next SELECTCUT;
		}

		# We don't want to seriously go past the top of the hour.  
		# Find out the cut length and skip it if it is too long.

		$currminute =`date "+%M"`; 
		$minutesleft = 60 - $currminute; 

		$_ = `mpck \"$cut\" | grep "time     "`;
		s/\s+/ /g;
		chop;
		($foo1, $foo2, $cuttime) = split(/ /);

		($cutminutes, $cutseconds_milli) = split(/:/,$cuttime);
		($cutseconds, $cutmilliseconds) = split(/./,$cutseconds_milli);
		$minutesover = $cutminutes - $minutesleft;

		if ($minutesover > 5) { 
			if ($debug > 0){
				print "	Skipped:\n   \"$cut\"\nas it will go past the top of the hour by $minutesover minutes\n";
			}
			if ($lookbackidx > 0){		# Don't drop to negative numbers.
				--$lookbackidx;		# We don't want to loop indefinity if we can't find a cut.
			}
			next SELECTCUT;
		}

		# If we got to here, we are playing this cut.
		close(RECENT);
		last;
	}

	# If we got to here, we are playing this cut.

	# Open and close the log as we may want other programs to play with these files while running.
	# For instance, to fix a $cutsplayedlog problem before the break.
	# 
	open (CUTSPLAYEDLOG, ">>$cutsplayedlog");
	open (FULLLOG, ">>$fulllog");
	$ctime=`date`; 
	chop($ctime);
	if (($cutname eq "") && ($artist eq "") && ($album eq "")){
		# We don't have any ID3 information that we can use so just log the file name.
		# Go through the log later to identify these cuts and populate the ID3 fields.
		print FULLLOG "$ctime - $cut\n";
	} else {
		# We do have ID3 information that we can use so log so we can announce it.
		print FULLLOG "$ctime	$artist	$album	$cutname\n";
		print CUTSPLAYEDLOG "$artist	$album	$cutname\n";
	}
	close(CUTSPLAYEDLOG);
	close(FULLLOG);

	# Create the HTML page...

	open (HTMLPAGE, ">$htmlpage");

	print HTMLPAGE "<HTML><META HTTP-EQUIV=\"REFRESH\" CONTENT=\"60\"><HEAD><TITLE>KUMR - Now playing...</TITLE></HEAD>\n";
	print HTMLPAGE "<BODY BGCOLOR=#000000 TEXT=#FFFF00 LINK=#FFFF00 ALINK=#FFFFFF VLINK=#FFFF00>\n";
	print HTMLPAGE "<CENTER><TABLE WIDTH=600 BORDER=0 CELLSPACING=3 CELLPADDING=2>\n";
	print HTMLPAGE "<TR><TD>\n";
	print HTMLPAGE "<FONT FACE=\"Arial, Helvetica\" SIZE=2><CENTER><B><FONT SIZE=+1>KUMR<BR><a href=\"http://yp.shoutcast.com/sbin/shoutcast-playlist.pls?addr=157.22.0.141:8080&file=filename.pls\">Now playing...</a></FONT></B></CENTER><BR></FONT>\n";
	print HTMLPAGE "<TABLE WIDTH=100% BORDER=0 CELLSPACING=3 CELLPADDING=2><TR><TD BGCOLOR=#005588><FONT FACE=\"Arial, Helvetica\" SIZE=2 SIZE=+2><B>The top entry is the most recent cut...</B></FONT></TD></TR></TABLE>\n";
	print HTMLPAGE "<BR><TABLE WIDTH=100% BORDER=0 CELLSPACING=3 CELLPADDING=2>\n";
	print HTMLPAGE "<TR><TD COLSPAN=2 BGCOLOR=#005588><B><FONT FACE=\"Arial, Helvetica\" SIZE=2 SIZE=+2>Last tracks played:</FONT></B></TD></TR>\n";

	open(RECENT_H, "tail -$htmllookback $fulllog | grep \"	\" |");

	$recentcutnum = 0;

	while(<RECENT_H>){
		chop;
		$recent_time = "";
		$recent_artist = "";
		$recent_album = "";
		$recent_cutname = "";
		if (m/.*	/){
			($recent_time,$recent_artist,$recent_album,$recent_cutname) = split(/	/);
			# This condition if for backwards compatibility for the old log format...
			if ($recent_cutname eq ""){
				$recent_cutname = $recent_album;
				$recent_album = $recent_artist;
				$recent_artist = $recent_time;
			}
		} else {
			$recent_artist = $_;
			$recent_cutname = $_;
		}
		$_ = "http://www.amazon.com/exec/obidos/external-search?mode=music&keyword=$recent_artist $recent_album";
		s/ /%20/g;
		$amazonurl = $_;
		$recentcut[$recentcutnum] = "<TR><TD WIDTH=35% BGCOLOR=#003355><FONT FACE=\"Arial, Helvetica\" SIZE=2>$recent_time</FONT></TD><TD WIDTH=65% BGCOLOR=#003355><FONT FACE=\"Arial, Helvetica\" SIZE=2><a href=\"$amazonurl\">$recent_artist - $recent_cutname</a></FONT></TD></TR>\n";
		$recentcutnum++;
	}
	while($recentcutnum > 0){
		$recentcutnum--;
		print HTMLPAGE $recentcut[$recentcutnum];
	}
	close(RECENT_H);
	print HTMLPAGE "<TR><TD WIDTH=35% BGCOLOR=#003355><FONT FACE=\"Arial, Helvetica\" SIZE=2>and so on...</FONT></TD><TD WIDTH=65% BGCOLOR=#003355><FONT FACE=\"Arial, Helvetica\" SIZE=2> </FONT></TD></TR>\n";
	close(RECENT_H);
	print HTMLPAGE "</TABLE>\n";
	print HTMLPAGE "<BR></TD></TR></TABLE></CENTER>\n";
	print HTMLPAGE "</BODY></HTML>\n";
	close(HTMLPAGE);

	# Play the damn cut!
	# `mpg123 -a /dev/dspW1 -b 1024 -v \"$cut\"`;
	`mpg123 -a /dev/dsp0.0 -b 2048 -v \"$cut\"`;
	# `mpg123 -b 2048 -v \"$cut\"`;
	sleep(3);
}
